// AppKit/CoreGraphics event objects, production queue, simulated source activation.
var failures = 0
let korean = "com.apple.inputmethod.Korean.2SetKorean"
let abc = "com.apple.keylayout.ABC"
let rshift: UInt64 = 0x20004
var checkedEvents = 0

func check(_ condition: Bool, _ message: String) {
    if !condition { failures += 1; print("FAIL: \(message)") }
}

func feed(_ hook: KeyboardHook, _ type: CGEventType, _ code: CGKeyCode,
          _ flags: UInt64, record: (CGEvent) -> Void) {
    let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: type != .keyUp)!
    event.type = type
    event.flags = CGEventFlags(rawValue: flags)
    if let passed = hook.receive(type, event) { record(passed.takeUnretainedValue()) }
}

func drain(_ hook: KeyboardHook) {
    let deadline = Date().addingTimeInterval(4)
    while hook.pumping || !hook.queue.isEmpty || hook.controller.busy {
        if Date() >= deadline { fatalError("Queue did not drain") }
        RunLoop.main.run(until: Date().addingTimeInterval(0.001))
    }
}

// Real codes for /, 1, [, ], -, =, ;, ', comma, period, backslash, grave.
// Each is punctuation under Shift and must not require a source round trip.
for code: CGKeyCode in [44, 18, 33, 30, 27, 24, 41, 39, 43, 47, 42, 50] {
    probeSource = korean
    let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let controller = try Controller(journal: path)
    controller.baseline = korean; controller.baselineOwned = true
    let hook = KeyboardHook(controller)
    var transitions: [String] = []
    var delivered: [Int64] = []
    controller.activationOverride = { target, _, done in
        transitions.append(target)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { probeSource = target; done(true) }
    }
    let record: (CGEvent) -> Void = { e in
        if e.type == .keyDown { delivered.append(e.getIntegerValueField(.keyboardEventKeycode)) }
    }
    hook.deliver = record
    let start = ProcessInfo.processInfo.systemUptime
    feed(hook, .flagsChanged, 60, rshift, record: record)
    feed(hook, .keyDown, code, rshift, record: record)
    feed(hook, .keyUp, code, rshift, record: record)
    feed(hook, .flagsChanged, 60, 0, record: record)
    feed(hook, .keyDown, 0, 0, record: record)
    drain(hook)
    let ms = (ProcessInfo.processInfo.systemUptime - start) * 1000
    check(transitions.isEmpty, "Shift symbol \(code) caused \(transitions.count) transitions (\(Int(ms)) ms)")
    check(delivered == [Int64(code), 0], "symbol/following-letter event order")
    check(probeSource == korean, "symbol changed baseline")
    checkedEvents += delivered.count
    try? FileManager.default.removeItem(at: path)
}

// Shortcut modifiers must not activate temporary English even with right Shift.
for modifier: UInt64 in [0x40001, 0x100008, 0x80020] {
    probeSource = korean
    let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let controller = try Controller(journal: path)
    controller.baseline = korean; controller.baselineOwned = true
    let hook = KeyboardHook(controller)
    var transitions = 0
    controller.activationOverride = { target, _, done in transitions += 1; probeSource = target; done(true) }
    let record: (CGEvent) -> Void = { _ in }
    hook.deliver = record
    feed(hook, .flagsChanged, 60, rshift, record: record)
    feed(hook, .keyDown, 8, modifier | rshift, record: record)
    feed(hook, .flagsChanged, 60, modifier, record: record)
    drain(hook)
    check(transitions == 0, "modified shortcut caused an input source transition")
    try? FileManager.default.removeItem(at: path)
}

// Bursts exercise begin/end interlocks and lost releases.
for baseline in [korean, abc] {
    for lostRelease in [false, true] {
        probeSource = baseline
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let controller = try Controller(journal: path)
        controller.baseline = baseline; controller.baselineOwned = true
        let hook = KeyboardHook(controller)
        controller.activationOverride = { target, _, done in probeSource = target; done(true) }
        var actual: [String] = []
        var expected: [String] = []
        let record: (CGEvent) -> Void = { e in
            if e.type == .keyDown { actual.append("\(e.getIntegerValueField(.keyboardEventKeycode)):\(probeSource)") }
        }
        hook.deliver = record
        for _ in 0..<50 {
            feed(hook, .flagsChanged, 60, rshift, record: record)
            feed(hook, .keyDown, 0, rshift, record: record); expected.append("0:\(abc)")
            feed(hook, .keyUp, 0, rshift, record: record)
            if !lostRelease { feed(hook, .flagsChanged, 60, 0, record: record) }
            feed(hook, .keyDown, 1, 0, record: record); expected.append("1:\(baseline)")
            feed(hook, .keyUp, 1, 0, record: record)
        }
        drain(hook)
        check(actual == expected, "burst language/order baseline=\(baseline) lostRelease=\(lostRelease)")
        check(!controller.held && controller.original == nil, "burst did not restore baseline/journal")
        checkedEvents += actual.count
        try? FileManager.default.removeItem(at: path)
    }
}

// Both Shifts and F18 before/after the first temporary English letter.
for toggleBeforeLetter in [false, true] {
    probeSource = korean
    let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let controller = try Controller(journal: path)
    controller.baseline = korean; controller.baselineOwned = true
    let hook = KeyboardHook(controller)
    controller.activationOverride = { target, _, done in probeSource = target; done(true) }
    var actual: [String] = []
    let record: (CGEvent) -> Void = { e in
        if e.type == .keyDown { actual.append(probeSource) }
    }
    hook.deliver = record
    feed(hook, .flagsChanged, 56, 0x20002, record: record)
    feed(hook, .flagsChanged, 60, 0x20006, record: record)
    if toggleBeforeLetter { feed(hook, .keyDown, 79, 0x20006, record: record) }
    feed(hook, .keyDown, 0, 0x20006, record: record)
    if !toggleBeforeLetter { feed(hook, .keyDown, 79, 0x20006, record: record) }
    feed(hook, .flagsChanged, 60, 0x20002, record: record)
    feed(hook, .keyDown, 1, 0x20002, record: record)
    feed(hook, .flagsChanged, 56, 0, record: record)
    drain(hook)
    check(actual == [abc, abc], "both Shifts/F18 baseline, toggleBeforeLetter=\(toggleBeforeLetter)")
    check(!controller.held && !hook.rightHeld && controller.original == nil, "both Shifts release")
    checkedEvents += actual.count
    try? FileManager.default.removeItem(at: path)
}

// Real Controller failure context previously exceeded Darwin's datagram limit.
do {
    probeSource = abc
    let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let controller = try Controller(journal: path)
    controller.baseline = korean; controller.baselineOwned = true
    controller.diagnosticLog = { _ in }
    controller.activationOverride = { _, _, done in done(false) }
    for _ in 0..<12 { controller.receive(["command": "end"]) { _ in } }
    controller.receive(["command": "status"]) { response in
        guard let data = encodeSocketReply(response) else { fatalError("Missing socket response") }
        print("TRANSPORT:" + data.base64EncodedString())
    }
    try? FileManager.default.removeItem(at: path)
}
print("Pipeline: \(checkedEvents) key-down observations, \(failures) failures")
exit(failures == 0 ? 0 : 1)
