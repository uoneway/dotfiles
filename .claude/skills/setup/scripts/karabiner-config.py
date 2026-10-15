#!/usr/bin/env python3
"""Apply shared Karabiner settings while merging devices as whole entries."""

import copy
import json
import os
from pathlib import Path
import platform
import shutil
import sys
import tempfile


ROOT = Path(__file__).resolve().parents[4]
SOURCE = ROOT / "config/keyboard/karabiner.json"
TARGET = Path.home() / ".config/karabiner/karabiner.json"
BACKUP = ROOT / "backup/.config/karabiner/karabiner.json"


def device_key(device):
    identifiers = device.get("identifiers")
    if not isinstance(identifiers, dict) or not identifiers:
        raise ValueError("every device needs nonempty identifiers")
    return json.dumps(identifiers, sort_keys=True, separators=(",", ":"))


def unique_devices(devices):
    if not isinstance(devices, list):
        raise ValueError("devices must be an array")
    keys = [device_key(device) for device in devices]
    if len(keys) != len(set(keys)):
        raise ValueError("duplicate device identifiers")
    return keys


def profiles(config):
    if not isinstance(config, dict) or not isinstance(config.get("profiles"), list):
        raise ValueError("Karabiner config needs a profiles array")
    result = config["profiles"]
    names = []
    for profile in result:
        if not isinstance(profile, dict) or not isinstance(profile.get("name"), str):
            raise ValueError("every profile needs a name")
        names.append(profile["name"])
        unique_devices(profile.get("devices", []))
    if len(names) != len(set(names)):
        raise ValueError("duplicate profile names")
    return result


def merged(shared, local):
    """Replace all shared settings; replace or append each shared device by identifiers."""
    shared_profiles = profiles(shared)
    local_profile_list = profiles(local)
    local_profiles = {profile["name"]: profile for profile in local_profile_list}
    selected_local = next((profile for profile in local_profile_list if profile.get("selected")), None)
    result = copy.deepcopy(shared)
    for profile in result["profiles"]:
        old_profile = local_profiles.get(profile["name"])
        if old_profile is None and profile.get("selected"):
            old_profile = selected_local
        local_devices = (old_profile or {}).get("devices", [])
        shared_devices = profile.get("devices", [])
        replacements = {device_key(device): device for device in shared_devices}
        existing = {device_key(device) for device in local_devices}
        profile["devices"] = [copy.deepcopy(replacements.get(device_key(device), device))
                              for device in local_devices]
        profile["devices"].extend(copy.deepcopy(device) for device in shared_devices
                                  if device_key(device) not in existing)
    return result


def read_json(path):
    with path.open(encoding="utf-8") as file:
        return json.load(file)


def run(action, source=SOURCE, target=TARGET, backup=BACKUP, enabled=None):
    if enabled is None:
        enabled = platform.system() == "Darwin" and Path("/Applications/Karabiner-Elements.app").exists()
    if not enabled:
        print("  [skip] Karabiner: macOS app not installed")
        return 0
    if not source.exists():
        print("  [skip] Karabiner: shared config not found")
        return 0
    if target.is_symlink():
        raise ValueError(f"Karabiner target must be a regular file: {target}")
    shared = read_json(source)
    local = read_json(target) if target.exists() else {"profiles": []}
    desired = merged(shared, local)
    if target.exists() and local == desired:
        print("  [ok] Karabiner: shared settings and devices in sync")
        return 0
    if action == "check":
        print("  [fail] Karabiner: settings drifted (run dotfiles apply)")
        return 1
    target.parent.mkdir(parents=True, exist_ok=True)
    if target.exists() and not backup.exists():
        backup.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(target, backup)
    mode = target.stat().st_mode & 0o777 if target.exists() else 0o600
    fd, temporary = tempfile.mkstemp(prefix=".karabiner.", suffix=".json", dir=target.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as file:
            json.dump(desired, file, ensure_ascii=False, indent=4)
            file.write("\n")
        os.chmod(temporary, mode)
        os.replace(temporary, target)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
    print("  [ok] Karabiner: shared settings applied; devices merged")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 2 or sys.argv[1] not in ("apply", "check"):
        raise SystemExit("Usage: karabiner-config.py apply|check")
    try:
        raise SystemExit(run(sys.argv[1]))
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(f"  [fail] Karabiner: {error}", file=sys.stderr)
        raise SystemExit(1)
