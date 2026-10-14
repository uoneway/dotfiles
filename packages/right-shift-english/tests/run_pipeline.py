#!/usr/bin/env python3
"""Exercise the production Controller/KeyboardHook without changing the desktop.

Only the TIS source getter/setter are replaced in a temporary compilation unit.
Activation is injected at the existing Controller seam; CGEvents are passed
directly to receive(), never posted to the user's keyboard or applications.
This checks event ordering and buffering, not an application's IME composition.
"""
import pathlib
import base64
import json
import socket
import subprocess
import sys
import tempfile

root = pathlib.Path(__file__).resolve().parents[1]
version = sys.argv[1] if len(sys.argv) > 1 else "1.0.5"
source = (root / version / "ShiftEnglish.swift").read_text()
existing = "--existing-tests" in sys.argv
if existing:
    source = source.split("\ndo {\n    try FileManager.default.createDirectory(at: directory", 1)[0]
else:
    source = source.split("\nfunc interruptionSelfTest()", 1)[0]
start = source.index("func currentID() -> String {")
end = source.index("\nfunc findSource(", start)
source = source[:start] + '''var probeSource = "com.apple.inputmethod.Korean.2SetKorean"
func currentID() -> String { probeSource }
''' + source[end:]
start = source.index("func select(_ id: String) -> Bool {")
end = source.index("\nfunc socketAddress(", start)
source = source[:start] + '''func select(_ id: String) -> Bool {
    probeSource = id
    return true
}
''' + source[end:]
if "func encodeSocketReply(" not in source:
    source += "\nfunc encodeSocketReply(_ result: [String: Any]) -> Data? { try? JSONSerialization.data(withJSONObject: result) }\n"
with tempfile.TemporaryDirectory(prefix="ime-pipeline-") as tmp:
    if existing:
        start = source.index("let directory = ")
        end = source.index("\nlet socketPath", start)
        source = source[:start] + f"let directory = URL(fileURLWithPath: {json.dumps(tmp)})" + source[end:]
        start = source.index("    func post() -> Bool {")
        end = source.index("\n}\n", start)
        source = source[:start] + '''    func post() -> Bool {
        probeSource = probeSource == "com.apple.keylayout.ABC"
            ? "com.apple.inputmethod.Korean.2SetKorean" : "com.apple.keylayout.ABC"
        return true
    }
''' + source[end:]
    main = pathlib.Path(tmp) / "main.swift"
    main.write_text(source if existing else source + "\n" + (root / "tests/PipelineTests.swift").read_text())
    exe = pathlib.Path(tmp) / "pipeline"
    subprocess.run(["swiftc", "-O", str(main), "-o", str(exe)], check=True)
    if existing:
        for test in ("interruption", "recovery", "keyboard"):
            subprocess.run([str(exe), "--self-test-" + test], check=True)
        sys.exit(0)
    run = subprocess.run([str(exe)], capture_output=True, text=True)
    failed = run.returncode != 0
    for line in run.stdout.splitlines():
        if not line.startswith("TRANSPORT:"):
            print(line)
            continue
        data = base64.b64decode(line.removeprefix("TRANSPORT:"))
        receiver = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
        sender = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
        endpoint = str(pathlib.Path(tmp) / "reply")
        receiver.bind(endpoint)
        receiver.settimeout(1)
        try:
            sender.sendto(data, endpoint)
            result = json.loads(receiver.recv(65536))
            assert result["last_error"]["command"] == "end"
            print(f"PASS: failure status round trip, {len(data)} bytes")
        except (OSError, AssertionError) as error:
            failed = True
            print(f"FAIL: failure status round trip, {len(data)} bytes: {error}")
        finally:
            receiver.close()
            sender.close()
    if run.stderr:
        print(run.stderr, file=sys.stderr)
    sys.exit(1 if failed else 0)
