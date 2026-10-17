#!/usr/bin/env python3
"""Apply opted-in macOS keyboard preferences; check never writes settings."""

import json
from pathlib import Path
import platform
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[4]
SOURCE = ROOT / "config/keyboard/macos.json"
KEY = "TSMLanguageIndicatorEnabled"


def run(action, source=SOURCE):
    if platform.system() != "Darwin":
        print("  [skip] macOS keyboard: not macOS")
        return 0
    if not source.exists():
        print("  [skip] macOS keyboard: shared config not found")
        return 0
    settings = json.loads(source.read_text(encoding="utf-8"))
    if not isinstance(settings, dict) or set(settings) != {KEY}:
        raise ValueError(f"macOS keyboard config must contain only {KEY}")
    desired = settings[KEY]
    if type(desired) is not int or desired not in (0, 1):
        raise ValueError(f"{KEY} must be integer 0 or 1")

    value = subprocess.run(["/usr/bin/defaults", "read", "-g", KEY],
                           capture_output=True, text=True)
    kind = subprocess.run(["/usr/bin/defaults", "read-type", "-g", KEY],
                          capture_output=True, text=True)
    if (value.returncode == 0 and value.stdout.strip() == str(desired)
            and kind.returncode == 0 and kind.stdout.strip() == "Type is integer"):
        print(f"  [ok] macOS keyboard: {KEY} = {desired}")
        return 0
    if action == "check":
        print(f"  [fail] macOS keyboard: {KEY} drifted (run dotfiles apply)")
        return 1

    subprocess.run(["/usr/bin/defaults", "write", "-g", KEY, "-int", str(desired)],
                   check=True, capture_output=True, text=True)
    print(f"  [ok] macOS keyboard: applied {KEY} = {desired}")
    print("  [info] Relaunch apps to use the preference; log out and back in to apply everywhere.")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 2 or sys.argv[1] not in ("apply", "check"):
        raise SystemExit("Usage: macos-keyboard.py apply|check")
    try:
        raise SystemExit(run(sys.argv[1]))
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f"  [fail] macOS keyboard: {error}", file=sys.stderr)
        raise SystemExit(1)
