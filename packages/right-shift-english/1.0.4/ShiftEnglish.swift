import Cocoa
import Carbon
import Darwin

if CommandLine.arguments.contains("--version") { print("Right Shift English 1.0.4"); exit(0) }
if CommandLine.arguments.contains("--request-permission") {
    let trusted = CGRequestPostEventAccess()
    // macOS 27 can grant Accessibility independently of PostEvent. Request
    // the permission used by the filtering event tap and synthetic key events.
    if !trusted { RunLoop.current.run(until: Date(timeIntervalSinceNow: 1)) }
    exit(trusted ? 0 : 2)
}
if CommandLine.arguments.contains("--check-permission") { exit(CGPreflightPostEventAccess() ? 0 : 2) }

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

var selectionHistory: [[String: Any]] = []

func select(_ id: String) -> Bool {
    if currentID() == id { return true }
    let status: OSStatus?
    if let source = findSource(id) { status = TISSelectInputSource(source) }
    else { status = nil }
    let observed = currentID()
    selectionHistory.append(["uptime": ProcessInfo.processInfo.systemUptime, "target": id,
                             "os_status": status.map { Int($0) } ?? NSNull(),
                             "source_available": status != nil, "current": observed])
    if selectionHistory.count > 16 { selectionHistory.removeFirst() }
    return status == noErr && observed == id
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
    let transitionTimeout = 0.300
    var nextRequestID = 0
    var activeRequestID: Int?
    var activeDeadline = 0.0
    var activeStartedAt = 0.0
    var activeFinish: ((Bool) -> Void)?
    var interruptionReason: String?
    var sourceTrace: [[String: Any]] = []
    var stageTrace: [[String: Any]] = []
    var nativeShortcutPosted = false
    var recentTransitions: [[String: Any]] = []
    var pausedSource: String?
    var interruptedTransitions = 0
    var lateCompletions = 0
    var diagnosticContext: () -> [String: Any] = { [:] }
    var diagnosticLog: ([String: Any]) -> Void = { details in
        if let data = try? JSONSerialization.data(withJSONObject: details, options: .sortedKeys),
           let line = String(data: data, encoding: .utf8) {
            fputs("ShiftEnglish: diagnostic \(line)\n", stderr)
        }
    }
    var consecutiveFailures = 0
    var lastError: [String: Any]?
    var transitionStage = "idle"
    var recoveryAllowed = true
    let restoreURL: URL
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

    init(journal: URL = journalURL) throws {
        restoreURL = journal
        guard findSource(english) != nil else {
            throw NSError(domain: "ShiftEnglish", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "ABC input source is unavailable"])
        }
        if let data = try? Data(contentsOf: restoreURL),
           let saved = try? JSONSerialization.jsonObject(with: data) as? [String: String],
           let id = saved["original"] { original = id; baseline = id; baselineOwned = true }
    }

    func restore() {
        // Keep the journal for startup recovery when exiting. An immediate
        // successful TIS return alone is not a durable completion signal.
        if recoveryAllowed, let id = original { _ = select(id) }
    }

    func reconcile() {
        if !recoveryAllowed {
            let source = currentID()
            if let previous = pausedSource, previous != source {
                diagnosticLog(["at": ISO8601DateFormatter().string(from: Date()),
                               "outcome": "source_changed_while_paused", "previous": previous,
                               "current": source, "last_request": nextRequestID,
                               "pipeline": diagnosticContext()])
            }
            pausedSource = source
        }
        if !busy, queue.isEmpty, recoveryAllowed {
            if !held, original != nil { receive(["command": "end"]) { _ in } }
            else if baselineOwned, currentID() != (held ? english : baseline) {
                receive(["command": "repair"]) { _ in }
            }
        }
    }

    func noteStage(_ stage: String) {
        transitionStage = stage
        stageTrace.append(["stage": stage,
                           "elapsed_ms": (ProcessInfo.processInfo.systemUptime - activeStartedAt) * 1000])
        if stageTrace.count > 12 { stageTrace.removeFirst() }
        observeSource()
    }

    func observeSource() {
        let source = currentID()
        if sourceTrace.last?["source"] as? String != source {
            sourceTrace.append(["source": source, "stage": transitionStage,
                                "elapsed_ms": (ProcessInfo.processInfo.systemUptime - activeStartedAt) * 1000])
            if sourceTrace.count > 12 { sourceTrace.removeFirst() }
        }
    }

    func expediteForUserAction(_ command: String) {
        guard let id = activeRequestID else { return }
        let now = ProcessInfo.processInfo.systemUptime
        // Preserve normal rapid typing. Only interrupt a transition already stalled
        // beyond the usual activation window; queued earlier text keeps its order.
        guard now - activeStartedAt >= 0.100 else { return }
        interruptionReason = "new_user_action:" + command
        activeDeadline = min(activeDeadline, now + 0.025)
        scheduleDeadline(id)
    }

    func scheduleDeadline(_ id: Int) {
        let delay = max(0, activeDeadline - ProcessInfo.processInfo.systemUptime)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard self.activeRequestID == id else { return }
            if ProcessInfo.processInfo.systemUptime >= self.activeDeadline {
                self.activeFinish?(false)
            } else { self.scheduleDeadline(id) }
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
        nextRequestID += 1
        let requestID = nextRequestID
        activeStartedAt = start
        sourceTrace = []
        stageTrace = []
        nativeShortcutPosted = false
        interruptionReason = nil
        noteStage("dispatch")
        let initialSource = currentID()
        let initialApp = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown"
        received += 1
        var target: String?
        var restoring = false
        var valid = true
        // Only an explicit language/Shift action resumes recovery after a failure.
        let command = message["command"] as? String
        if ["begin", "end", "toggle", "select"].contains(command ?? "") {
            recoveryAllowed = true
        }
        switch command {
        case "begin":
            if original == nil {
                let id = baselineOwned ? baseline : currentID()
                baseline = id
                do {
                    guard !id.isEmpty else { throw NSError(domain: "ShiftEnglish", code: 3) }
                    let data = try JSONSerialization.data(withJSONObject: ["original": id])
                    try data.write(to: restoreURL, options: .atomic)
                    chmod(restoreURL.path, 0o600)
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
                try? data?.write(to: restoreURL, options: .atomic)
                target = english
            } else { target = baseline }
        case "repair":
            target = held ? english : baseline
            if currentID() != target { repairs += 1 }
        case "status", "barrier": break
        case "select":
            if held || original != nil { valid = false }
            else if let id = message["source"] as? String { target = id; baseline = id; baselineOwned = true }
            else { valid = false }
        default: valid = false
        }
        var completed = false
        var lateReported = false
        let finish: (Bool) -> Void = { ok in
            guard !completed else {
                if !lateReported {
                    lateReported = true
                    self.lateCompletions += 1
                    self.diagnosticLog(["at": ISO8601DateFormatter().string(from: Date()),
                                        "outcome": "late_completion_ignored", "request_id": requestID,
                                        "latest_request_id": self.nextRequestID, "current": currentID()])
                }
                return
            }
            completed = true
            self.observeSource()
            let superseded = self.interruptionReason != nil
            let outcome = ok ? "ok" : (superseded ? "superseded" : "failed")
            let elapsed = (ProcessInfo.processInfo.systemUptime - start) * 1000
            var details: [String: Any] = ["at": ISO8601DateFormatter().string(from: Date()),
                "request_id": requestID, "command": command ?? "unknown", "outcome": outcome,
                "stage": self.transitionStage, "target": target ?? "", "initial_source": initialSource,
                "current": currentID(), "elapsed_ms": elapsed, "timeout_ms": self.transitionTimeout * 1000,
                "source_trace": self.sourceTrace, "stage_trace": self.stageTrace,
                "native_shortcut_posted": self.nativeShortcutPosted,
                "baseline": self.baseline, "original": self.original ?? NSNull(), "held": self.held,
                "initial_app": initialApp, "pipeline": self.diagnosticContext(),
                "app": NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown"]
            if let shortcut = PreviousSourceShortcut.configured() {
                details["shortcut"] = ["key": Int(shortcut.key), "flags": shortcut.flags.rawValue]
            } else { details["shortcut"] = "disabled_or_invalid" }
            if let reason = self.interruptionReason { details["reason"] = reason }
            else if !ok { details["reason"] = elapsed >= self.transitionTimeout * 1000 ? "timeout" : "transition_rejected" }
            self.activeRequestID = nil
            self.activeFinish = nil
            if !ok {
                if superseded { self.interruptedTransitions += 1 }
                else { self.errors += 1; self.consecutiveFailures += 1 }
                self.recoveryAllowed = false
                self.pausedSource = currentID()
                details["automatic_recovery"] = false
                details["version"] = "1.0.4"
                details["os"] = ProcessInfo.processInfo.operatingSystemVersionString
                details["controller_queued_commands"] = self.queue.count
                details["permissions"] = ["accessibility": AXIsProcessTrusted(),
                                           "post_events": CGPreflightPostEventAccess(),
                                           "listen_events": CGPreflightListenEventAccess()]
                details["source_selections"] = selectionHistory.filter {
                    ($0["uptime"] as? Double ?? 0) >= start
                }.map { selection -> [String: Any] in
                    var item = selection
                    item["elapsed_ms"] = ((item.removeValue(forKey: "uptime") as? Double ?? start) - start) * 1000
                    return item
                }
                details["recent_transitions"] = self.recentTransitions
                self.lastError = details
                self.diagnosticLog(details)
            } else if target != nil {
                self.consecutiveFailures = 0
                self.recoveryAllowed = true
                self.pausedSource = nil
            }
            if target != nil || !ok {
                self.recentTransitions.append(["request_id": requestID, "command": command ?? "unknown",
                    "outcome": outcome, "target": target ?? "", "current": currentID(), "elapsed_ms": elapsed])
                if self.recentTransitions.count > 8 { self.recentTransitions.removeFirst() }
            }
            if ok, let target {
                if restoring { self.baseline = target; self.baselineOwned = true }
            }
            if ok && restoring {
                self.original = nil
                try? FileManager.default.removeItem(at: self.restoreURL)
            }
            self.maximumMilliseconds = max(self.maximumMilliseconds,
                (ProcessInfo.processInfo.systemUptime - start) * 1000)
            completion(["ok": ok, "held": self.held, "current": currentID(),
                        "original": self.original ?? NSNull(), "baseline": self.baseline,
                        "baseline_owned": self.baselineOwned, "repairs": self.repairs,
                        "received": self.received, "native_activations": self.nativeActivations,
                        "errors": self.errors, "maximum_operation_ms": self.maximumMilliseconds,
                        "consecutive_failures": self.consecutiveFailures,
                        "automatic_recovery": self.recoveryAllowed,
                        "transition_timeout_ms": self.transitionTimeout * 1000,
                        "interrupted_transitions": self.interruptedTransitions,
                        "late_completions": self.lateCompletions,
                        "last_error": self.lastError ?? NSNull()])
            self.busy = false
            self.pump()
        }
        if !valid { finish(false) }
        else if let target {
            activeRequestID = requestID
            activeDeadline = start + transitionTimeout
            activeFinish = finish
            scheduleDeadline(requestID)
            if let activationOverride { activationOverride(target, activeDeadline, finish) }
            else { activate(target, deadline: activeDeadline, requestID: requestID, completion: finish) }
        }
        else { finish(true) }
    }

    func activate(_ target: String, deadline: Double, requestID: Int, completion: @escaping (Bool) -> Void) {
        guard activeRequestID == requestID else { return }
        noteStage("settle_source")
        guard target == "com.apple.inputmethod.Korean.2SetKorean", currentID() != target else {
            settle(target, deadline: deadline, stableSince: nil, requestID: requestID, completion: completion)
            return
        }
        noteStage("read_previous_source_shortcut")
        guard let shortcut = PreviousSourceShortcut.configured() else { completion(false); return }
        noteStage("prepare_korean_source")
        guard select(target) else {
            completion(false); return
        }
        // Establish the desired source as the previous source, then let the
        // system perform the final activation inside the focused app.
        settle(target, deadline: deadline, stableSince: nil, requestID: requestID) { ok in
            guard self.activeRequestID == requestID else { return }
            guard ok else { completion(false); return }
            self.noteStage("prepare_english_source")
            guard select(self.english) else { completion(false); return }
            self.settle(self.english, deadline: deadline, stableSince: nil, requestID: requestID) { ok in
                guard self.activeRequestID == requestID else { return }
                guard ok else { completion(false); return }
                self.noteStage("post_previous_source_shortcut")
                guard shortcut.post() else { completion(false); return }
                self.nativeShortcutPosted = true
                self.noteStage("wait_native_korean_activation")
                self.nativeActivations += 1
                self.waitForNativeActivation(target, deadline: deadline, requestID: requestID, completion: completion)
            }
        }
    }

    func waitForNativeActivation(_ target: String, deadline: Double, stableSince: Double? = nil,
                                 requestID: Int, completion: @escaping (Bool) -> Void) {
        // Never use TIS to repair this wait: it would hide a failed shortcut
        // behind the same menu-only selection that caused the original bug.
        guard activeRequestID == requestID else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let deadline = min(deadline, activeDeadline)
        observeSource()
        if now >= deadline { completion(false); return }
        let stable = currentID() == target ? (stableSince ?? now) : nil
        if let stable, now - stable >= 0.025 { completion(true); return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.005) {
            self.waitForNativeActivation(target, deadline: deadline, stableSince: stable, requestID: requestID, completion: completion)
        }
    }

    func settle(_ target: String, deadline: Double, stableSince: Double?,
                requestID: Int, completion: @escaping (Bool) -> Void) {
        guard activeRequestID == requestID else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let deadline = min(deadline, activeDeadline)
        observeSource()
        if now >= deadline { completion(false); return }
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
            self.settle(target, deadline: deadline, stableSince: nextStable, requestID: requestID, completion: completion)
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
    var bufferedSince: Double?
    var deliver: (CGEvent) -> Void = { $0.post(tap: .cgSessionEventTap) }

    init(_ controller: Controller) {
        self.controller = controller
        controller.diagnosticContext = { [weak self] in
            guard let self else { return [:] }
            let events = self.queue.reduce(0) { count, job in
                if case .event = job { return count + 1 }; return count
            }
            return ["queued_events": events, "queued_commands": self.queue.count - events,
                    "right_shift_held": self.rightHeld, "pumping": self.pumping,
                    "buffered_ms": self.bufferedSince.map {
                        (ProcessInfo.processInfo.systemUptime - $0) * 1000
                    } ?? 0]
        }
    }

    func enqueueEvent(_ event: CGEvent) {
        if bufferedSince == nil { bufferedSince = ProcessInfo.processInfo.systemUptime }
        queue.append(.event(event))
    }

    func enqueueUserCommand(_ command: String) {
        queue.append(.command(command))
        controller.expediteForUserAction(command)
        pump()
    }

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
                enqueueUserCommand("toggle")
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
                controller.expediteForUserAction(down ? "begin" : "end")
                if let copy = event.copy() { enqueueEvent(copy) }
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
                controller.expediteForUserAction(down ? "begin" : "end")
                if let copy = event.copy() { enqueueEvent(copy) }
                pump()
                return nil
            }
        }
        if pumping || !queue.isEmpty || controller.busy {
            if let copy = event.copy() { enqueueEvent(copy) }
            pump()
            return nil
        }
        if type == .keyDown,
           (rightHeld || controller.baselineOwned),
           controller.recoveryAllowed,
           currentID() != (rightHeld ? controller.english : controller.baseline) {
            queue.append(.command("repair"))
            if let copy = event.copy() { enqueueEvent(copy) }
            pump()
            return nil
        }
        deliveredAt = ProcessInfo.processInfo.systemUptime
        return Unmanaged.passUnretained(event)
    }

    func pump() {
        if !pumping, queue.isEmpty { bufferedSince = nil; return }
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

func interruptionSelfTest() throws {
    let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let controller = try Controller(journal: path)
    let hook = KeyboardHook(controller)
    var stale: ((Bool) -> Void)?
    var targets: [String] = []
    var delivered = 0
    var diagnostics: [[String: Any]] = []
    controller.diagnosticLog = { diagnostics.append($0) }
    var secondStartedAt: Double?
    let start = ProcessInfo.processInfo.systemUptime
    controller.baseline = controller.english
    controller.baselineOwned = true
    controller.activationOverride = { target, _, done in
        targets.append(target)
        if targets.count == 1 { stale = done }
        else { secondStartedAt = ProcessInfo.processInfo.systemUptime; done(true) }
    }
    hook.deliver = { _ in delivered += 1 }
    hook.queue.append(.command("end")); hook.pump()
    RunLoop.main.run(until: Date().addingTimeInterval(0.14))
    let key = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)!
    key.flags = []
    _ = hook.receive(.keyDown, key)
    let toggle = CGEvent(keyboardEventSource: nil, virtualKey: 79, keyDown: true)!
    _ = hook.receive(.keyDown, toggle)
    RunLoop.main.run(until: Date().addingTimeInterval(0.10))
    var failures = 0
    if secondStartedAt == nil || secondStartedAt! - start > 0.24 || delivered != 1 {
        print("FAIL: newer language action is blocked behind the stalled transition"); failures += 1
    }
    let received = controller.received
    let baseline = controller.baseline
    let held = controller.held
    stale?(true)
    RunLoop.main.run(until: Date().addingTimeInterval(0.01))
    if controller.received != received || controller.busy || controller.baseline != baseline || controller.held != held {
        print("FAIL: obsolete completion changed the new request"); failures += 1
    }
    let sourceBeforeStalePoll = currentID()
    var stalePollFinished = false
    controller.settle(controller.english, deadline: ProcessInfo.processInfo.systemUptime + 1,
                      stableSince: nil, requestID: 1) { _ in stalePollFinished = true }
    if stalePollFinished || currentID() != sourceBeforeStalePoll {
        print("FAIL: stale source poll was not ignored"); failures += 1
    }
    // A transition which never calls its completion must still time out promptly.
    controller.activationOverride = { _, _, _ in }
    controller.receive(["command": "repair"]) { _ in }
    RunLoop.main.run(until: Date().addingTimeInterval(0.36))
    if controller.busy || controller.recoveryAllowed {
        print("FAIL: failed transition holds input beyond the short deadline"); failures += 1
    }
    let outcomes = diagnostics.compactMap { $0["outcome"] as? String }
    if outcomes != ["superseded", "late_completion_ignored", "failed"]
        || diagnostics.last?["elapsed_ms"] == nil || diagnostics.last?["pipeline"] == nil
        || diagnostics.last?["stage_trace"] == nil || diagnostics.last?["source_trace"] == nil
        || diagnostics.last?["source_selections"] == nil || diagnostics.last?["permissions"] == nil {
        print("FAIL: diagnostics do not distinguish interruption, stale completion and timeout"); failures += 1
    }
    print("Interruption regression: \(failures) failures; outcomes: \(outcomes)")
    if failures != 0 { exit(1) }
}

if CommandLine.arguments.contains("--self-test-interruption") {
    do { try interruptionSelfTest(); exit(0) }
    catch { fputs("Interruption self-test: \(error)\n", stderr); exit(1) }
}

func recoverySelfTest() throws {
    let testDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: testDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: testDirectory) }
    let testJournal = testDirectory.appendingPathComponent("restore.json")
    let desired = currentID() == "com.apple.keylayout.ABC"
        ? "com.apple.inputmethod.Korean.2SetKorean" : "com.apple.keylayout.ABC"
    try JSONSerialization.data(withJSONObject: ["original": desired]).write(to: testJournal)
    let controller = try Controller(journal: testJournal)
    controller.activationOverride = { _, _, done in done(false) }
    controller.receive(["command": "end"]) { _ in }
    var failures = 0
    for _ in 0..<1000 { controller.reconcile() }
    if controller.errors != 1 || controller.recoveryAllowed {
        print("FAIL: failed activation triggered automatic recovery"); failures += 1
    }
    if controller.original != desired || !FileManager.default.fileExists(atPath: testJournal.path) {
        print("FAIL: failed restore lost the pending baseline"); failures += 1
    }
    let hook = KeyboardHook(controller)
    var delivered = 0
    hook.deliver = { _ in delivered += 1 }
    let key = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)!
    key.flags = []
    if hook.receive(.keyDown, key) != nil { delivered += 1 }
    hook.queue.append(.event(key))
    hook.pump()
    RunLoop.main.run(until: Date().addingTimeInterval(0.01))
    if delivered != 2 || !hook.queue.isEmpty || controller.errors != 1 {
        print("FAIL: ordinary input retried or remained blocked"); failures += 1
    }
    for command in ["status", "barrier"] {
        controller.receive(["command": command]) { _ in }
    }
    if controller.errors != 1 || controller.recoveryAllowed {
        print("FAIL: reading status resumed automatic recovery"); failures += 1
    }
    // A new user action may try again, even if the next attempt also fails.
    controller.receive(["command": "end"]) { _ in }
    if controller.errors != 2 || controller.recoveryAllowed {
        print("FAIL: explicit retry was suppressed or failed to pause"); failures += 1
    }
    controller.activationOverride = { _, _, done in done(true) }
    controller.receive(["command": "end"]) { _ in }
    if controller.consecutiveFailures != 0 || !controller.recoveryAllowed
        || controller.original != nil || FileManager.default.fileExists(atPath: testJournal.path) {
        print("FAIL: successful explicit retry did not finish restoration"); failures += 1
    }
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
