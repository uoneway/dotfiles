"""macOS-only preference application and read-only drift checks."""

import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch


SCRIPT = Path(__file__).resolve().parents[1] / ".claude/skills/setup/scripts/macos-keyboard.py"
spec = importlib.util.spec_from_file_location("macos_keyboard", SCRIPT)
keyboard = importlib.util.module_from_spec(spec)
spec.loader.exec_module(keyboard)


class MacOSKeyboardTest(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.source = Path(tmp.name) / "macos.json"
        self.source.write_text(json.dumps({
            "TSMLanguageIndicatorEnabled": 0,
            "InitialKeyRepeat": 11,
            "KeyRepeat": 1,
        }))
        self.values = {}
        self.writes = []
        self.platform = patch.object(keyboard.platform, "system", return_value="Darwin")
        self.platform.start()
        self.addCleanup(self.platform.stop)
        self.commands = patch.object(keyboard.subprocess, "run", side_effect=self.defaults)
        self.mock_run = self.commands.start()
        self.addCleanup(self.commands.stop)

    def defaults(self, args, **kwargs):
        action, key = args[1], args[3]
        if action == "write":
            self.writes.append(args)
            self.values[key] = (args[5], "integer")
            return subprocess.CompletedProcess(args, 0, "", "")
        if key not in self.values:
            return subprocess.CompletedProcess(args, 1, "", "missing")
        value, kind = self.values[key]
        output = value if action == "read" else f"Type is {kind}"
        return subprocess.CompletedProcess(args, 0, output + "\n", "")

    def test_missing_preference_is_drift_then_apply_is_idempotent(self):
        self.assertEqual(keyboard.run("check", self.source), 1)
        self.assertEqual(self.writes, [])
        self.assertEqual(keyboard.run("apply", self.source), 0)
        self.assertEqual(self.values["TSMLanguageIndicatorEnabled"], ("0", "integer"))
        self.assertEqual(keyboard.run("apply", self.source), 0)
        self.assertEqual(keyboard.run("check", self.source), 0)
        self.assertEqual(len(self.writes), 1)

    def test_linux_and_absent_config_do_not_touch_preferences(self):
        with patch.object(keyboard.platform, "system", return_value="Linux"):
            self.assertEqual(keyboard.run("apply", self.source), 0)
            self.assertEqual(keyboard.run("check", self.source), 0)
        self.source.unlink()
        self.assertEqual(keyboard.run("apply", self.source), 0)
        self.mock_run.assert_not_called()

    def test_string_zero_is_repaired_as_integer(self):
        self.values["TSMLanguageIndicatorEnabled"] = ("0", "string")
        self.assertEqual(keyboard.run("check", self.source), 1)
        self.assertEqual(self.writes, [])
        self.assertEqual(keyboard.run("apply", self.source), 0)
        self.assertEqual(self.values["TSMLanguageIndicatorEnabled"], ("0", "integer"))

    def test_invalid_config_never_touches_preferences(self):
        for data in ({"TSMLanguageIndicatorEnabled": False},
                     {"TSMLanguageIndicatorEnabled": 2}, {"unknown": 0}):
            with self.subTest(data=data):
                self.source.write_text(json.dumps(data))
                with self.assertRaises(ValueError):
                    keyboard.run("apply", self.source)
        self.mock_run.assert_not_called()

    def test_failed_write_is_not_reported_as_success(self):
        def fail_write(args, **kwargs):
            if args[1] == "write":
                raise subprocess.CalledProcessError(1, args)
            return self.defaults(args, **kwargs)
        self.mock_run.side_effect = fail_write
        with self.assertRaises(subprocess.CalledProcessError):
            keyboard.run("apply", self.source)


if __name__ == "__main__":
    unittest.main()
