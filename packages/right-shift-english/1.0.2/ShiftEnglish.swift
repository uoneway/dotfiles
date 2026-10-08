import Cocoa
import Carbon
import Darwin

if CommandLine.arguments.contains("--version") { print("Right Shift English 1.0.2"); exit(0) }
if CommandLine.arguments.contains("--check-permission") { exit(AXIsProcessTrusted() ? 0 : 2) }

// All input-source operations run on the main run loop. The socket receiver
// only queues messages; it never selects sources from a worker thread.
let directory = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".local/share/karabiner-shift-english")
let socketPath = directory.appendingPathComponent("commands.sock").path
let journalURL = directory.appendingPathComponent("restore.json")

func sourceID(_ source: TISInputSource) -> String {
    guard let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return "" }
    return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
}

func currentID() -> String {
    sourceID(TISCopyCurrentKeyboardInputSource().takeRetainedValue())
}

func findSource(_ id: String) -> TISInputSource? {
    let sources = TISCreateInputSourceList(nil, false).takeRetainedValue() as! [TISInputSource]
    return sources.first { sourceID($0) == id }
}

func select(_ id: String) -> Bool {
    if currentID() == id { return true }
    guard let source = findSource(id) else { return false }
    return TISSelectInputSource(source) == noErr && currentID() == id
}

func socketAddress(_ path: String) -> sockaddr_un {
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
    let bytes = Array(path.utf8) + [0]
    precondition(bytes.count <= MemoryLayout.size(ofValue: address.sun_path))
    withUnsafeMutableBytes(of: &address.sun_path) { target in
        target.copyBytes(from: bytes)
    }
    return address
}

// TIS can update the menu bar without activating a CJK input context in
// the focused app. Complete CJK selections through macOS's previous-source
// shortcut, rather than trusting the source ID alone (Karabiner issue #1602).
struct PreviousSourceShortcut {
    let key: CGKeyCode
    let flags: CGEventFlags

    static func configured() -> PreviousSourceShortcut? {
        let preferences = CFPreferencesCopyAppValue("AppleSymbolicHotKeys" as CFString,
                                                    "com.apple.symbolichotkeys" as CFString)
            as? [String: Any]
        // macOS's default is Control-Space when no override is persisted.
        guard let entry = preferences?["60"] as? [String: Any] else {
            return PreviousSourceShortcut(key: 49, flags: .maskControl)
        }
        guard entry["enabled"] as? Bool == true,
              let value = entry["value"] as? [String: Any],
              let parameters = value["parameters"] as? [NSNumber], parameters.count == 3,
              parameters[1].intValue >= 0, parameters[1].intValue <= 127 else { return nil }
        return PreviousSourceShortcut(key: CGKeyCode(parameters[1].intValue),
                                      flags: CGEventFlags(rawValue: parameters[2].uint64Value))
    }

    func post() -> Bool {
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: false) else { return false }
        for event in [down, up] {
            event.flags = flags
            event.setIntegerValueField(.eventSourceUserData, value: 0x5348494654454E47)
            event.post(tap: .cgSessionEventTap)
        }
        return true
    }
}

final class Controller {
    // Fault injection only used by the recovery regression; production uses activate.
    var activationOverride: ((String, Double, @escaping (Bool) -> Void) -> Void)?
    var recoveryClock: () -> Double = { ProcessInfo.processInfo.systemUptime }
    var consecutiveFailures = 0
    var retryAfter = 0.0
    var lastError: [String: Any]?
    var transitionStage = "idle"
    var recoveryAllowed: Bool { recoveryClock() >= retryAfter }
    var original: String?
    var held = false
    var baseline = currentID()
    // F18 and explicit selections own this state. Temporary or late TIS
    // activations must never silently redefine the user's baseline.
    var baselineOwned = false
    var repairs = 0
    var received = 0
    var errors = 0
    var maximumMilliseconds = 0.0
    var nativeActivations = 0
    let english = "com.apple.keylayout.ABC"
    var busy = false
    var queue: [([String: Any], ([String: Any]) -> Void)] = []

    init() throws {
        guard findSource(english) != nil else {
            throw NSError(domain: "ShiftEnglish", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "ABC input source is unavailable"])
        }
        if let data = try? Data(contentsOf: journalURL),
           let saved = try? JSONSerialization.jsonObject(with: data) as? [String: String],
           let id = saved["original"] { original = id; baseline = id; baselineOwned = true }
    }

    func restore() {
        // Keep the journal for startup recovery when exiting. An immediate
        // successful TIS return alone is not a durable completion signal.
        if let id = original { _ = select(id) }
    }

    func reconcile() {
        if !busy, queue.isEmpty, recoveryAllowed {
            if !held, original != nil { receive(["command": "end"]) { _ in } }
            else if baselineOwned, currentID() != (held ? english : baseline) {
                receive(["command": "repair"]) { _ in }
            }
        }
    }

    func receive(_ message: [String: Any], completion: @escaping ([String: Any]) -> Void) {
        queue.append((message, completion))
        pump()
    }

    func pump() {
        guard !busy, !queue.isEmpty else { return }
        busy = true
        let (message, completion) = queue.removeFirst()
        let start = ProcessInfo.processInfo.systemUptime
        transitionStage = "dispatch"
        received += 1
        var target: String?
        var restoring = false
        var valid = true
        switch message["command"] as? String {
        case "begin":
            if original == nil {
                let id = baselineOwned ? baseline : currentID()
                baseline = id
                do {
                    guard !id.isEmpty else { throw NSError(domain: "ShiftEnglish", code: 3) }
                    let data = try JSONSerialization.data(withJSONObject: ["original": id])
                    try data.write(to: journalURL, options: .atomic)
                    chmod(journalURL.path, 0o600)
                    original = id
                } catch { valid = false }
            }
            if valid { baselineOwned = true; held = true; target = english }
        case "end":
            held = false
            target = original ?? baseline
            restoring = true
        case "toggle":
            if !baselineOwned { baseline = currentID() }
            baselineOwned = true
            baseline = baseline == english ? "com.apple.inputmethod.Korean.2SetKorean" : english
            if held {
                original = baseline
                let data = try? JSONSerialization.data(withJSONObject: ["original": baseline])
                try? data?.write(to: journalURL, options: .atomic)
                target = english
            } else { target = baseline }
        case "repair":
            target = held ? english : baseline
            if currentID() != target { repairs += 1 }
        case "status":
            if baselineOwned { target = held ? english : baseline }
        case "barrier": break
        case "select":
            if held || original != nil { valid = false }
            else if let id = message["source"] as? String { target = id; baseline = id; baselineOwned = true }
            else { valid = false }
        default: valid = false
        }
        let finish: (Bool) -> Void = { ok in
            if !ok {
                self.errors += 1
                self.consecutiveFailures += 1
                let delay = min(30.0, pow(2.0, Double(min(self.consecutiveFailures - 1, 5))))
                self.retryAfter = self.recoveryClock() + delay
                self.lastError = ["at": ISO8601DateFormatter().string(from: Date()),
                                  "command": message["command"] as? String ?? "unknown",
                                  "stage": self.transitionStage, "target": target ?? "",
                                  "current": currentID(), "retry_in_seconds": delay]
                if let data = try? JSONSerialization.data(withJSONObject: self.lastError!, options: .sortedKeys),
                   let details = String(data: data, encoding: .utf8) {
                    fputs("ShiftEnglish: transition failed \(details)\n", stderr)
                }
            } else if target != nil {
                self.consecutiveFailures = 0
                self.retryAfter = 0
            }
            if ok, let target {
                if restoring { self.baseline = target; self.baselineOwned = true }
            }
            if ok && restoring {
                self.original = nil
                try? FileManager.default.removeItem(at: journalURL)
            }
            self.maximumMilliseconds = max(self.maximumMilliseconds,
                (ProcessInfo.processInfo.systemUptime - start) * 1000)
            completion(["ok": ok, "held": self.held, "current": currentID(),
                        "original": self.original ?? NSNull(), "baseline": self.baseline,
                        "baseline_owned": self.baselineOwned, "repairs": self.repairs,
                        "received": self.received, "native_activations": self.nativeActivations,
                        "errors": self.errors, "maximum_operation_ms": self.maximumMilliseconds,
                        "consecutive_failures": self.consecutiveFailures,
                        "retry_in_seconds": max(0, self.retryAfter - self.recoveryClock()),
                        "last_error": self.lastError ?? NSNull()])
            self.busy = false
            self.pump()
        }
        if !valid { finish(false) }
        else if let target {
            if let activationOverride { activationOverride(target, start + 2, finish) }
            else { activate(target, deadline: start + 2, completion: finish) }
        }
        else { finish(true) }
    }

    func activate(_ target: String, deadline: Double, completion: @escaping (Bool) -> Void) {
        transitionStage = "settle_source"
        guard target == "com.apple.inputmethod.Korean.2SetKorean", currentID() != target else {
            settle(target, deadline: deadline, stableSince: nil, completion: completion)
            return
        }
        transitionStage = "read_previous_source_shortcut"
        guard let shortcut = PreviousSourceShortcut.configured() else { completion(false); return }
        transitionStage = "prepare_korean_source"
        guard select(target) else {
            completion(false); return
        }
        // Establish the desired source as the previous source, then let the
        // system perform the final activation inside the focused app.
        settle(target, deadline: deadline, stableSince: nil) { ok in
            guard ok else { completion(false); return }
            self.transitionStage = "prepare_english_source"
            guard select(self.english) else { completion(false); return }
            self.settle(self.english, deadline: deadline, stableSince: nil) { ok in
                guard ok else { completion(false); return }
                self.transitionStage = "post_previous_source_shortcut"
                guard shortcut.post() else { completion(false); return }
                self.transitionStage = "wait_native_korean_activation"
                self.nativeActivations += 1
                self.waitForNativeActivation(target, deadline: deadline, completion: completion)
            }
        }
    }

    func waitForNativeActivation(_ target: String, deadline: Double, stableSince: Double? = nil,
                                 completion: @escaping (Bool) -> Void) {
        // Never use TIS to repair this wait: it would hide a failed shortcut
        // behind the same menu-only selection that caused the original bug.
        let now = ProcessInfo.processInfo.systemUptime
        let stable = currentID() == target ? (stableSince ?? now) : nil
        if let stable, now - stable >= 0.025 { completion(true); return }
        if now >= deadline { completion(false); return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.005) {
            self.waitForNativeActivation(target, deadline: deadline, stableSince: stable, completion: completion)
        }
    }

    func settle(_ target: String, deadline: Double, stableSince: Double?,
                completion: @escaping (Bool) -> Void) {
        let now = ProcessInfo.processInfo.systemUptime
        var stable = stableSince
        if currentID() != target {
            stable = nil
            if !select(target) && now >= deadline { completion(false); return }
        } else {
            if stable == nil { stable = now }
            if now - stable! >= 0.025 { completion(true); return }
        }
        if now >= deadline { completion(false); return }
        let nextStable = stable
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.005) {
            self.settle(target, deadline: deadline, stableSince: nextStable, completion: completion)
        }
    }
}

// A native event tap provides the missing interlock: events received during a
// source transition wait for the controller's acknowledgement. Karabiner's
// async user commands alone cannot pause subsequent keyboard events.
final class KeyboardHook {
    enum Job {
        case event(CGEvent)
        case command(String)
    }
    let controller: Controller
    let marker: Int64 = 0x5348494654454E47
    var tap: CFMachPort?
    var rightHeld = false
    var pumping = false
    var queue: [Job] = []
    var deliveredAt = 0.0
    var deliver: (CGEvent) -> Void = { $0.post(tap: .cgSessionEventTap) }

    init(_ controller: Controller) { self.controller = controller }

    func start() throws {
        let mask = (CGEventMask(1) << CGEventType.keyDown.rawValue)
            | (CGEventMask(1) << CGEventType.keyUp.rawValue)
            | (CGEventMask(1) << CGEventType.flagsChanged.rawValue)
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                               options: .defaultTap, eventsOfInterest: mask,
                               callback: { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            let hook = Unmanaged<KeyboardHook>.fromOpaque(context).takeUnretainedValue()
            return hook.receive(type, event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque())
        guard let tap else {
            throw NSError(domain: "ShiftEnglish", code: 4,
                          userInfo: [NSLocalizedDescriptionKey: "Keyboard event tap is unavailable; Accessibility permission is required"])
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func receive(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        if event.getIntegerValueField(.eventSourceUserData) == marker {
            return Unmanaged.passUnretained(event)
        }
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        // F18 remains the user's language key. It changes the same baseline
        // as Shift restoration, so a manual toggle cannot race an old restore.
        if code == 79 {
            if type == .keyDown && event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
                queue.append(.command("toggle")); pump()
            }
            return nil
        }
        // Recover if the modifier's release event was lost (for example after
        // a keyboard disconnect), before allowing the next text event through.
        if (type == .keyDown || type == .flagsChanged), code != 60 {
            let down = event.flags.rawValue & 0x4 != 0
            if down != rightHeld {
                rightHeld = down
                queue.append(.command(down ? "begin" : "end"))
                if let copy = event.copy() { queue.append(.event(copy)) }
                pump()
                return nil
            }
        }
        if type == .flagsChanged && code == 60 {
            // NX_DEVICERSHIFTKEYMASK distinguishes releasing right Shift while
            // left Shift is still down. The aggregate shift flag cannot do so.
            let down = event.flags.rawValue & 0x4 != 0
            if down != rightHeld {
                rightHeld = down
                queue.append(.command(down ? "begin" : "end"))
                if let copy = event.copy() { queue.append(.event(copy)) }
                pump()
                return nil
            }
        }
        if pumping || !queue.isEmpty || controller.busy {
            if let copy = event.copy() { queue.append(.event(copy)) }
            pump()
            return nil
        }
        if type == .keyDown,
           (rightHeld || controller.baselineOwned),
           controller.recoveryAllowed,
           currentID() != (rightHeld ? controller.english : controller.baseline) {
            queue.append(.command("repair"))
            if let copy = event.copy() { queue.append(.event(copy)) }
            pump()
            return nil
        }
        deliveredAt = ProcessInfo.processInfo.systemUptime
        return Unmanaged.passUnretained(event)
    }

    func pump() {
        guard !pumping, !queue.isEmpty else { return }
        if controller.busy {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.002) { self.pump() }
            return
        }
        pumping = true
        // Validate at delivery, not just arrival: buffered events can outlive
        // a TIS change, and rightHeld already reflects later queued modifiers.
        if case .event(let event) = queue[0], event.type == .keyDown,
           controller.baselineOwned,
           controller.recoveryAllowed,
           currentID() != (controller.held ? controller.english : controller.baseline) {
            controller.receive(["command": "repair"]) { _ in
                self.pumping = false; self.pump()
            }
            return
        }
        switch queue.removeFirst() {
        case .event(let event):
            event.setIntegerValueField(.eventSourceUserData, value: marker)
            deliver(event)
            deliveredAt = ProcessInfo.processInfo.systemUptime
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.002) {
                self.pumping = false; self.pump()
            }
        case .command(let command):
            // Give the previous text event time to reach the app before
            // restoring its input source. Subsequent events remain buffered.
            let elapsed = ProcessInfo.processInfo.systemUptime - deliveredAt
            let delay = command == "end" ? max(0, 0.015 - elapsed) : 0
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                self.controller.receive(["command": command]) { _ in
                    self.pumping = false; self.pump()
                }
            }
        }
    }
}

func recoverySelfTest() throws {
    let controller = try Controller()
    // Preserve any real pending restore; the test's injected failures never select sources.
    let pending = controller.original
    var clock = 100.0
    controller.recoveryClock = { clock }
    controller.baseline = currentID() == controller.english
        ? "com.apple.inputmethod.Korean.2SetKorean" : controller.english
    controller.baselineOwned = true
    controller.original = nil
    controller.activationOverride = { _, _, done in done(false) }
    controller.receive(["command": "repair"]) { _ in }
    for _ in 0..<100 { controller.reconcile() }
    var failures = 0
    if controller.errors != 1 {
        print("FAIL: failed activation was retried immediately: \(controller.errors) attempts")
        failures += 1
    }
    let hook = KeyboardHook(controller)
    var delivered = 0
    hook.deliver = { _ in delivered += 1 }
    let key = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)!
    key.flags = []
    hook.queue.append(.event(key))
    hook.pump()
    RunLoop.main.run(until: Date().addingTimeInterval(0.01))
    if delivered != 1 || !hook.queue.isEmpty || controller.errors != 1 {
        print("FAIL: input remained blocked by a failed repair")
        failures += 1
    }
    clock += 1.0
    controller.reconcile()
    if controller.errors != 2 { print("FAIL: recovery did not resume after cooldown"); failures += 1 }
    for _ in 0..<100 { controller.reconcile() }
    if controller.errors != 2 { print("FAIL: second cooldown was ignored"); failures += 1 }
    // A barrier must neither select a source nor clear the cooldown.
    controller.receive(["command": "barrier"]) { _ in }
    controller.reconcile()
    if controller.errors != 2 { print("FAIL: status polling cleared cooldown"); failures += 1 }
    clock += 2.0
    for expectedDelay in [4.0, 8.0, 16.0, 30.0, 30.0] {
        controller.reconcile()
        if controller.retryAfter - clock != expectedDelay {
            print("FAIL: incorrect bounded retry interval"); failures += 1
        }
        clock = controller.retryAfter
    }
    controller.baseline = currentID()
    controller.activationOverride = { _, _, done in done(true) }
    controller.receive(["command": "repair"]) { _ in }
    if controller.consecutiveFailures != 0 || !controller.recoveryAllowed {
        print("FAIL: successful activation did not clear backoff"); failures += 1
    }
    controller.original = pending
    print("Recovery regression: \(failures) failures")
    if failures != 0 { exit(1) }
}

if CommandLine.arguments.contains("--self-test-recovery") {
    do { try recoverySelfTest(); exit(0) }
    catch { fputs("Recovery self-test: \(error)\n", stderr); exit(1) }
}

func keyboardSelfTest() throws {
    let saved = currentID()
    let controller = try Controller()
    let hook = KeyboardHook(controller)
    var expected: [String] = []
    var observed: [String] = []
    var failures = 0
    func record(_ event: CGEvent) {
        if event.type == .keyDown && event.getIntegerValueField(.keyboardEventKeycode) == 0 {
            observed.append(currentID())
        }
    }
    hook.deliver = record
    func feed(_ type: CGEventType, _ code: CGKeyCode, _ flags: UInt64) {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: type != .keyUp)!
        event.type = type
        event.flags = CGEventFlags(rawValue: flags)
        if hook.receive(type, event) != nil { record(event) }
    }
    func drain() {
        let deadline = Date().addingTimeInterval(60)
        while hook.pumping || !hook.queue.isEmpty || controller.busy {
            if Date() >= deadline { fatalError("Keyboard pipeline did not drain") }
            RunLoop.main.run(until: Date().addingTimeInterval(0.005))
        }
    }
    func establish(_ id: String) {
        controller.receive(["command": "select", "source": id]) { result in
            if !(result["ok"] as? Bool ?? false) { failures += 1 }
        }
        drain()
    }
    for baseline in ["com.apple.inputmethod.Korean.2SetKorean", controller.english] {
        establish(baseline)
        // All events arrive immediately; source transitions must buffer them.
        for _ in 0..<100 {
            feed(.flagsChanged, 60, 0x20004)
            feed(.keyDown, 0, 0x20004); expected.append(controller.english)
            feed(.keyUp, 0, 0x20004)
            feed(.flagsChanged, 60, 0)
            feed(.keyDown, 0, 0); expected.append(baseline)
            feed(.keyUp, 0, 0)
        }
        drain()
        // Missing right-Shift key-up: the following unshifted text must cause
        // restoration before it is delivered, rather than staying in ABC.
        feed(.flagsChanged, 60, 0x20004)
        feed(.keyDown, 0, 0x20004); expected.append(controller.english)
        feed(.keyUp, 0, 0x20004)
        feed(.keyDown, 0, 0); expected.append(baseline)
        feed(.keyUp, 0, 0)
        drain()
        // Both Shifts: release right Shift while left Shift remains down.
        feed(.flagsChanged, 56, 0x20002)
        feed(.flagsChanged, 60, 0x20006)
        feed(.keyDown, 0, 0x20006); expected.append(controller.english)
        feed(.keyUp, 0, 0x20006)
        feed(.flagsChanged, 60, 0x20002)
        feed(.keyDown, 0, 0x20002); expected.append(baseline)
        feed(.keyUp, 0, 0x20002)
        feed(.flagsChanged, 56, 0)
        drain()
        // Another modifier is pressed after Shift and remains down on release.
        for (code, flags) in [(CGKeyCode(55), UInt64(0x100008)),
                              (CGKeyCode(59), UInt64(0x40001)),
                              (CGKeyCode(58), UInt64(0x80020))] {
            feed(.flagsChanged, 60, 0x20004)
            feed(.flagsChanged, code, flags | 0x20004)
            feed(.keyDown, 0, flags | 0x20004); expected.append(controller.english)
            feed(.keyUp, 0, flags | 0x20004)
            feed(.flagsChanged, 60, flags)
            feed(.flagsChanged, code, 0)
            feed(.keyDown, 0, 0); expected.append(baseline)
            feed(.keyUp, 0, 0)
            drain()
        }
        // Manual language toggle during the temporary-English session.
        let toggled = baseline == controller.english ? "com.apple.inputmethod.Korean.2SetKorean" : controller.english
        feed(.flagsChanged, 60, 0x20004)
        feed(.keyDown, 79, 0x20004); feed(.keyUp, 79, 0x20004)
        feed(.keyDown, 0, 0x20004); expected.append(controller.english)
        feed(.keyUp, 0, 0x20004)
        feed(.flagsChanged, 60, 0)
        feed(.keyDown, 0, 0); expected.append(toggled)
        feed(.keyUp, 0, 0)
        drain()
    }
    // Regression: a late ABC activation must not become the next baseline.
    establish("com.apple.inputmethod.Korean.2SetKorean")
    feed(.flagsChanged, 60, 0x20004)
    feed(.keyDown, 0, 0x20004); expected.append(controller.english)
    feed(.keyUp, 0, 0x20004)
    feed(.flagsChanged, 60, 0)
    drain()
    RunLoop.main.run(until: Date().addingTimeInterval(0.85))
    _ = select(controller.english)
    feed(.keyDown, 0, 0); expected.append("com.apple.inputmethod.Korean.2SetKorean")
    feed(.keyUp, 0, 0)
    drain()
    feed(.flagsChanged, 60, 0x20004)
    feed(.keyDown, 0, 0x20004); expected.append(controller.english)
    feed(.keyUp, 0, 0x20004)
    feed(.flagsChanged, 60, 0)
    feed(.keyDown, 0, 0); expected.append("com.apple.inputmethod.Korean.2SetKorean")
    feed(.keyUp, 0, 0)
    drain()
    // Regression: an app-side source change after replayed Shift-up occurs
    // before a queued unshifted letter is delivered.
    establish("com.apple.inputmethod.Korean.2SetKorean")
    hook.deliver = { event in
        record(event)
        if event.type == .flagsChanged,
           event.getIntegerValueField(.keyboardEventKeycode) == 60,
           event.flags.rawValue & 0x4 == 0 { _ = select(controller.english) }
    }
    feed(.flagsChanged, 60, 0x20004)
    feed(.keyDown, 0, 0x20004); expected.append(controller.english)
    feed(.keyUp, 0, 0x20004)
    feed(.flagsChanged, 60, 0)
    feed(.keyDown, 0, 0); expected.append("com.apple.inputmethod.Korean.2SetKorean")
    feed(.keyUp, 0, 0)
    drain()
    hook.deliver = record
    if expected != observed {
        failures += zip(expected, observed).filter { $0 != $1 }.count
        failures += abs(expected.count - observed.count)
    }
    establish(saved)
    print("Keyboard pipeline: \(observed.count) key-down checks, \(failures) failures; API errors: \(controller.errors)")
    if failures != 0 || controller.errors != 0 { exit(1) }
}

if CommandLine.arguments.contains("--self-test-keyboard") {
    do { try keyboardSelfTest(); exit(0) }
    catch { fputs("Keyboard self-test: \(error)\n", stderr); exit(1) }
}

do {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    chmod(directory.path, 0o700)
    let lockFD = open(directory.appendingPathComponent("daemon.lock").path, O_CREAT | O_RDWR, 0o600)
    guard lockFD >= 0, flock(lockFD, LOCK_EX | LOCK_NB) == 0 else { exit(0) }
    let controller = try Controller()
    let keyboard = KeyboardHook(controller)
    if !CommandLine.arguments.contains("--sources-only") { try keyboard.start() }
    let fd = socket(AF_UNIX, SOCK_DGRAM, 0)
    guard fd >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
    unlink(socketPath)
    var address = socketAddress(socketPath)
    let bound = withUnsafePointer(to: &address) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
    }
    guard bound == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
    chmod(socketPath, 0o600)

    DispatchQueue.global(qos: .userInteractive).async {
        var buffer = [UInt8](repeating: 0, count: 8192)
        while true {
            let count = recv(fd, &buffer, buffer.count, 0)
            if count <= 0 { if errno == EINTR { continue }; break }
            let data = Data(buffer.prefix(count))
            guard let message = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            DispatchQueue.main.async {
                controller.receive(message) { result in
                if let reply = message["reply_to"] as? String,
                   reply.hasPrefix("/tmp/shift-english-test-"),
                   let data = try? JSONSerialization.data(withJSONObject: result) {
                    var destination = socketAddress(reply)
                    data.withUnsafeBytes { bytes in
                        withUnsafePointer(to: &destination) { pointer in
                            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                                _ = sendto(fd, bytes.baseAddress, bytes.count, 0, $0,
                                           socklen_t(MemoryLayout<sockaddr_un>.size))
                            }
                        }
                    }
                }
                }
            }
        }
    }

    // Failed selections stay pending and are retried without replacing the
    // saved original. The retry runs even when no further keys arrive.
    let retry = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in controller.reconcile() }
    RunLoop.main.add(retry, forMode: .common)
    var signalSources: [DispatchSourceSignal] = []
    for number in [SIGTERM, SIGINT, SIGHUP] {
        signal(number, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
        source.setEventHandler {
            controller.held = false
            controller.restore()
            unlink(socketPath)
            exit(0)
        }
        source.resume()
        signalSources.append(source)
    }
    print("ShiftEnglish ready: \(socketPath)")
    fflush(stdout)
    withExtendedLifetime((signalSources, keyboard)) { CFRunLoopRun() }
} catch {
    fputs("ShiftEnglish: \(error)\n", stderr)
    exit(1)
}
