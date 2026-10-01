#!/usr/bin/env python3
"""Resolve local settings and inherited registered-machine settings."""
import argparse
from pathlib import Path
import re
import sys

try:
    import tomllib
except ImportError:
    sys.path.insert(0, str(Path(__file__).resolve().parent / "vendor"))
    import tomli as tomllib

ROOT = Path(__file__).resolve().parents[4]
SETTING_KEYS = {"apps", "components", "transport", "path", "agents_addition", "zsh_addition"}


def validate_settings(entry, label):
    if not isinstance(entry, dict):
        raise ValueError(f"{label}: settings must be a table")
    for key in SETTING_KEYS.intersection(entry):
        value = entry[key]
        if key == "apps":
            if not isinstance(value, list) or any(not isinstance(item, str) for item in value):
                raise ValueError(f"{label}: apps must be an array of app names")
            if len(set(value)) != len(value):
                raise ValueError(f"{label}: duplicate app names")
        elif not isinstance(value, str) or any(char in value for char in "\n\r|"):
            raise ValueError(f"{label}: {key} must be a single-line string")
        elif key == "components" and value:
            components = value.split(",")
            if len(set(components)) != len(components) or set(components) - {"shell", "claude", "codex", "gemini"}:
                raise ValueError(f"{label}: invalid components")
        elif key == "transport" and value not in ("hub", "direct"):
            raise ValueError(f"{label}: transport must be hub or direct")
        elif key in ("agents_addition", "zsh_addition") and value and not re.fullmatch(r"[A-Za-z0-9._-]+", value):
            raise ValueError(f"{label}: invalid {key}")
    return entry


def load(root=ROOT):
    path = root / "config/machines.toml"
    if not path.exists():
        path = root / "templates/machines.toml"
    if not path.exists():
        return {"local": {}, "defaults": {}, "machines": {}}
    with path.open("rb") as file:
        data = tomllib.load(file)
    for section in ("local", "defaults"):
        validate_settings(data.get(section, {}), section)
    machines = data.get("machines", {})
    if not isinstance(machines, dict):
        raise ValueError("machines must be a table")
    for name, entry in machines.items():
        if not re.fullmatch(r"[A-Za-z0-9._-]+", name):
            raise ValueError(f"invalid machine name: {name}")
        validate_settings(entry, name)
        host = entry.get("host", "")
        if not isinstance(host, str) or any(char in host for char in "\n\r|"):
            raise ValueError(f"{name}: invalid host")
    return data


def settings(name=None, root=ROOT, data=None):
    data = load(root) if data is None else data
    if not name:
        return dict(data.get("local", {}))
    machines = data.get("machines", {})
    if not re.fullmatch(r"[A-Za-z0-9._-]+", name) or name not in machines:
        raise ValueError(f"unknown machine: {name}")
    inherited = {key: value for key, value in data.get("defaults", {}).items() if key in SETTING_KEYS}
    return dict(inherited, **machines[name])


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("list", "get"))
    parser.add_argument("name", nargs="?", default="")
    parser.add_argument("key", nargs="?", choices=sorted(SETTING_KEYS))
    args = parser.parse_args(argv)
    try:
        data = load()
        if args.action == "get":
            if args.key is None:
                raise ValueError("get requires machine name (empty for local) and setting key")
            value = settings(args.name, data=data).get(args.key, "")
            if isinstance(value, list):
                import json
                print(json.dumps(value))
            else:
                print(value)
        else:
            for name in data.get("machines", {}):
                entry = settings(name, data=data)
                print("|".join((name, entry.get("host", ""), entry.get("components", ""),
                                entry.get("transport", "hub"), entry.get("path", "~/dotfiles"))))
        return 0
    except (ValueError, OSError) as error:
        print(f"[error] machine configuration: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
