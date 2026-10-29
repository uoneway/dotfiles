#!/usr/bin/env python3
"""Print persistent installer notices after the surrounding operation finishes."""
import argparse
import json
import os
from pathlib import Path
import sys


def validate(value):
    if (not isinstance(value, dict) or value.get("schema") != 1
            or not isinstance(value.get("id"), str) or not value["id"]
            or not isinstance(value.get("message"), str) or not value["message"].strip()
            or len(value["message"]) > 16384):
        raise ValueError("invalid notice record")
    return value


def read_file(path):
    if path.stat().st_size > 1024 * 1024:
        raise ValueError("notice file is too large")
    return json.loads(path.read_text())


def local_notices(home=None):
    home = Path(home or Path.home())
    state = Path(os.environ.get("XDG_STATE_HOME", str(home / ".local/state")))
    directory = state / "dotfiles/notices"
    result = []
    for path in sorted(directory.glob("*.json")):
        try:
            result.append(validate(read_file(path)))
        except (OSError, ValueError) as error:
            print(f"[warn] Could not read notice {path.name}: {error}", file=sys.stderr)
    return result


def emit(home=None, reports=()):
    groups = [("local", local_notices(home))]
    for label, filename in reports:
        try:
            values = read_file(Path(filename))
            if not isinstance(values, list):
                raise ValueError("expected a list of notices")
            groups.append((label, [validate(value) for value in values]))
        except (OSError, ValueError) as error:
            print(f"[warn] Could not read notices for {label}: {error}", file=sys.stderr)
    groups = [(label, values) for label, values in groups if values]
    if not groups:
        return
    print("\n=== 확인이 필요한 알림 ===", flush=True)
    for label, values in groups:
        print(f"[{label}]", flush=True)
        for value in values:
            print(value["message"], flush=True)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--json", action="store_true", help="read local notices without changing them")
    parser.add_argument("--report", action="append", nargs=2, default=[], metavar=("MACHINE", "JSON_FILE"))
    args = parser.parse_args(argv)
    if args.json:
        if args.report:
            parser.error("--json cannot be combined with --report")
        print(json.dumps(local_notices(), ensure_ascii=False))
    else:
        emit(reports=args.report)
    return 0


if __name__ == "__main__":
    sys.exit(main())
