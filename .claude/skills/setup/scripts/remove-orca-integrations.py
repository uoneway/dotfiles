#!/usr/bin/env python3
"""Explicit Orca uninstall cleanup; preview by default, write with --apply.

Remove Orca hooks from local settings and dotfiles backups without changing
shared base settings, other hooks, credentials, or conversation history.
"""

import argparse
import json
import os
from pathlib import Path
import re
import stat
import tempfile


def clean_json(data):
    hooks = data.get('hooks', {})
    if isinstance(hooks, dict):
        for event, groups in list(hooks.items()):
            if not isinstance(groups, list):
                continue
            kept = []
            for group in groups:
                if not isinstance(group, dict) or not isinstance(group.get('hooks'), list):
                    kept.append(group)
                    continue
                entries = group['hooks']
                remaining = [h for h in entries if not (
                    isinstance(h, dict) and isinstance(h.get('command'), str)
                    and ('orca-agent-hook-form=' in h['command']
                         or '.orca/agent-hooks/' in h['command'])
                )]
                if len(remaining) == len(entries):
                    kept.append(group)
                elif remaining:
                    kept.append({**group, 'hooks': remaining})
            if kept:
                hooks[event] = kept
            else:
                del hooks[event]
    plugins = data.get('plugin')
    if isinstance(plugins, list):
        data['plugin'] = [p for p in plugins if not (
            isinstance(p, str) and p.startswith('file://')
            and '/opencode/plugins/orca-opencode-status-tui/tui.js' in p
        )]
    return data


def clean_toml(text, home):
    # Only the verified Orca rate-limit working directory trust grant.
    section = '[projects.' + json.dumps(str(home / 'Library/Application Support/orca/rate-limit-pty-cwd')) + ']'
    pattern = r'(?m)^' + re.escape(section) + r'\r?\n[^\[]*?(?=^\[|\Z)'
    def remove_known(match):
        body = match.group().splitlines()[1:]
        values = [line.strip() for line in body if line.strip() and not line.lstrip().startswith('#')]
        return '' if values == ['trust_level = "trusted"'] else match.group()
    return re.sub(pattern, remove_known, text)


def candidates(home, dotfiles):
    for directory, patterns in [
        (home / '.codex', ('hooks.json*', 'config.toml*')),
        (home / '.claude', ('settings.json*',)),
        (home / '.config/opencode', ('tui.json',)),
    ]:
        for pattern in patterns:
            yield from directory.glob(pattern)
    backup = dotfiles / 'backup'
    if backup.exists():
        for path in backup.rglob('*'):
            if path.name in ('settings.json', 'hooks.json', 'config.toml', 'codex-live-copy.toml'):
                yield path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--apply', action='store_true')
    parser.add_argument('--home', type=Path, default=Path.home())
    parser.add_argument('--dotfiles', type=Path, default=Path(__file__).resolve().parents[4])
    args = parser.parse_args()
    for path in sorted(set(candidates(args.home, args.dotfiles))):
        if not path.is_file() or path.is_symlink():
            continue
        old = path.read_text()
        if 'orca' not in old.lower():
            continue
        if path.name.startswith(('settings.json', 'hooks.json')) or path.name == 'tui.json':
            data = json.loads(old)
            before = json.dumps(data, sort_keys=True)
            clean_json(data)
            if json.dumps(data, sort_keys=True) == before:
                continue
            new = json.dumps(data, indent=2, ensure_ascii=False) + '\n'
        else:
            new = clean_toml(old, args.home)
        if new == old:
            continue
        print(('clean ' if args.apply else 'would clean ') + str(path))
        if args.apply:
            mode = stat.S_IMODE(path.stat().st_mode)
            descriptor, temp = tempfile.mkstemp(dir=path.parent, prefix='.orca-cleanup-')
            try:
                with os.fdopen(descriptor, 'w') as output:
                    output.write(new)
                os.chmod(temp, mode)
                os.replace(temp, path)
            finally:
                if os.path.exists(temp):
                    os.unlink(temp)


if __name__ == '__main__':
    main()
