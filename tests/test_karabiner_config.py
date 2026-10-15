"""Karabiner apply keeps local-only devices and replaces shared ones atomically."""

import importlib.util
import json
from pathlib import Path
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / ".claude/skills/setup/scripts/karabiner-config.py"
spec = importlib.util.spec_from_file_location("karabiner_config", SCRIPT)
karabiner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(karabiner)


def device(product, mapping):
    return {"identifiers": {"vendor_id": 42, "product_id": product, "is_keyboard": True},
            "simple_modifications": [mapping]}


class KarabinerConfigTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        root = Path(self.tmp.name)
        self.source = root / "shared.json"
        self.target = root / "karabiner/karabiner.json"
        self.backup = root / "backup/karabiner.json"
        self.target.parent.mkdir()
        self.shared = {"global": {"show_in_menu_bar": False}, "profiles": [
            {"name": "Default profile", "selected": True,
             "simple_modifications": [{"shared": "new"}],
             "devices": [device(1, "shared-new"), device(3, "shared-added")]}]}
        self.local = {"global": {"show_in_menu_bar": True, "local_only": True},
                      "profiles": [{"name": "Default profile", "selected": True,
                                    "simple_modifications": [{"old": "local"}],
                                    "devices": [device(1, "shared-old"), device(2, "local-only")]}],
                      "local_root": "removed"}

    def write(self):
        self.source.write_text(json.dumps(self.shared))
        self.target.write_text(json.dumps(self.local))

    def apply(self, action="apply"):
        return karabiner.run(action, self.source, self.target, self.backup, enabled=True)

    def test_common_replaced_and_devices_replaced_or_appended(self):
        self.write()
        self.assertEqual(self.apply("check"), 1)
        self.assertEqual(self.apply(), 0)
        result = json.loads(self.target.read_text())
        self.assertEqual(result["global"], self.shared["global"])
        self.assertNotIn("local_root", result)
        profile = result["profiles"][0]
        self.assertEqual(profile["simple_modifications"], [{"shared": "new"}])
        self.assertEqual([item["identifiers"]["product_id"] for item in profile["devices"]], [1, 2, 3])
        self.assertEqual([item["simple_modifications"][0] for item in profile["devices"]],
                         ["shared-new", "local-only", "shared-added"])
        self.assertEqual(json.loads(self.backup.read_text()), self.local)
        before = self.target.read_bytes()
        self.assertEqual(self.apply(), 0)
        self.assertEqual(self.apply("check"), 0)
        self.assertEqual(self.target.read_bytes(), before)

    def test_bad_source_leaves_target_untouched(self):
        self.write()
        self.shared["profiles"][0]["devices"].append(device(1, "duplicate"))
        self.source.write_text(json.dumps(self.shared))
        with self.assertRaisesRegex(ValueError, "duplicate device"):
            self.apply()
        self.assertEqual(json.loads(self.target.read_text()), self.local)
        self.assertFalse(self.backup.exists())

    def test_selected_profile_renamed_on_another_mac_keeps_its_devices(self):
        self.local["profiles"][0]["name"] = "Laptop profile"
        self.write()
        self.assertEqual(self.apply(), 0)
        profile = json.loads(self.target.read_text())["profiles"][0]
        self.assertEqual(profile["name"], "Default profile")
        self.assertEqual([item["identifiers"]["product_id"] for item in profile["devices"]], [1, 2, 3])

    def test_missing_target_creates_shared_config(self):
        self.source.write_text(json.dumps(self.shared))
        self.assertEqual(self.apply(), 0)
        self.assertEqual(json.loads(self.target.read_text()), self.shared)
        self.assertEqual(self.target.stat().st_mode & 0o777, 0o600)


if __name__ == "__main__":
    unittest.main()
