#!/usr/bin/env python3
"""Overlay shared TOML/JSON and retire only unchanged, previously managed values.

The existing AWK renderer deliberately supports a limited base syntax. Every
render is validated against the complete semantic result before any writes.
"""
import argparse
import copy
import hashlib
import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import sys
import tempfile

SCRIPTS = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPTS / "vendor"))
import tomli

MISSING = object()


def load_json(text):
    def reject_constant(value):
        raise ValueError('non-finite JSON numbers are not supported')
    def unique_keys(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise ValueError('duplicate JSON keys; no config written')
            result[key] = value
        return result
    value = json.loads(text, parse_constant=reject_constant, object_pairs_hook=unique_keys)
    if not isinstance(value, dict):
        raise ValueError('settings must be a JSON object')
    return value


def expand_marketplace_paths(base, root):
    # Store the effective base so later removals compare the value actually
    # applied on this machine, even if the root or HOME subsequently changes.
    for entry in (base.get('extraKnownMarketplaces') or {}).values():
        source = entry.get('source') if isinstance(entry, dict) else None
        if isinstance(source, dict) and isinstance(source.get('path'), str):
            path = source['path']
            source['path'] = (str(root / path[len('~/dotfiles/'):])
                              if path.startswith('~/dotfiles/') else os.path.expanduser(path))


def leaves(value, prefix=()):
    for key, child in value.items():
        path = prefix + (key,)
        if isinstance(child, dict):
            yield from leaves(child, path)
        else:
            yield path, child


def get(value, path):
    for key in path:
        if not isinstance(value, dict) or key not in value:
            return MISSING
        value = value[key]
    return value


def equal(a, b):
    if type(a) is not type(b):
        return False
    if isinstance(a, dict):
        return a.keys() == b.keys() and all(equal(a[k], b[k]) for k in a)
    if isinstance(a, list):
        return len(a) == len(b) and all(equal(x, y) for x, y in zip(a, b))
    return a == b


def overlay(target, base, replace_tables=False):
    for key, value in base.items():
        if isinstance(value, dict):
            child = target.setdefault(key, {})
            if not isinstance(child, dict):
                if not replace_tables:
                    raise ValueError("base table conflicts with an existing scalar")
                child = target[key] = {}
            overlay(child, value, replace_tables)
        else:
            target[key] = value


def remove_assignments(source, removals):
    """Remove complete statements; do not match text inside multiline values.

    Unsupported inline-table removals are rejected by semantic verification.
    Headers remain, including empty tables, to preserve local table structure.
    """
    lines = source.splitlines(keepends=True)
    out, section, index = [], (), 0
    while index < len(lines):
        start = index
        line = lines[index]
        index += 1
        stripped = line.strip()
        if not stripped or stripped.startswith('#'):
            out.append(line)
            continue
        if stripped.startswith('['):
            # An array table and its descendants are never scalar removals.
            header = tomli.loads(line)
            def table_path(obj, path=()):
                if isinstance(obj, dict) and len(obj) == 1:
                    k, v = next(iter(obj.items()))
                    return table_path(v, path + (k,))
                return path if isinstance(obj, dict) else None
            section = table_path(header)
            out.append(line)
            continue
        statement = line
        while True:
            try:
                parsed = tomli.loads(statement)
                break
            except tomli.TOMLDecodeError:
                if index == len(lines):
                    raise ValueError("cannot safely locate TOML assignment")
                statement += lines[index]
                index += 1
        # A whole assignment can go only if every value in it is retired.
        paths = [section + p for p, _ in leaves(parsed)] if section is not None else []
        if not paths or not all(p in removals for p in paths):
            out.extend(lines[start:index])
    return ''.join(out)


def atomic_write(path, content, mode=0o600):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(prefix='.' + path.name + '.', dir=str(path.parent))
    try:
        with os.fdopen(fd, 'w', encoding='utf-8') as f:
            os.fchmod(f.fileno(), mode)
            f.write(content)
            f.flush()
            os.fsync(f.fileno())
        os.replace(name, path)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('base', type=Path)
    parser.add_argument('target', type=Path)
    parser.add_argument('--check', action='store_true')
    parser.add_argument('--format', choices=['toml', 'json'], default='toml')
    parser.add_argument('--claude-marketplace-root', type=Path)
    parser.add_argument('--migrations', type=Path)
    args = parser.parse_args()
    base_path = args.base.absolute()
    target = args.target.absolute()
    base_text = base_path.read_text(encoding='utf-8')
    load = tomli.loads if args.format == 'toml' else load_json
    base = load(base_text)
    snapshot_base = base_text
    if args.claude_marketplace_root:
        if args.format != 'json':
            raise ValueError('marketplace expansion requires JSON')
        expand_marketplace_paths(base, args.claude_marketplace_root)
        snapshot_base = json.dumps(base, ensure_ascii=False)
    exists = target.exists()
    original_text = target.read_text(encoding='utf-8') if exists else ''
    original = load(original_text) if exists else {}
    state_root = Path(os.environ.get('DOTFILES_STATE_DIR') or
                      str(Path(os.environ.get('XDG_STATE_HOME', str(Path.home() / '.local/state'))) / 'dotfiles'))
    identity = str(target)
    state_path = state_root / args.format / (hashlib.sha256(identity.encode()).hexdigest() + '.json')
    state_text = state_path.read_text(encoding='utf-8') if state_path.exists() else None
    state = json.loads(state_text) if state_text else {}
    if state and (state.get('version') != 1 or state.get('target') != identity or
                  state.get('base_path') != str(base_path)):
        raise ValueError('snapshot identity/version mismatch; inspect state before applying')
    previous_text = state.get('base', '' if args.format == 'toml' else '{}')
    previous = load(previous_text)
    candidates = {tuple(item['path']): item for item in state.get('pending', [])}
    for path, value in leaves(previous):
        if get(base, path) is MISSING:
            candidates[path] = {'path': list(path), 'source': previous_text}
    completed = set(state.get('migrations', []))
    if args.migrations:
        for migration in json.loads(args.migrations.read_text(encoding='utf-8')):
            if migration['id'] not in completed:
                path = tuple(migration['path'])
                candidates.setdefault(path, migration)
                completed.add(migration['id'])
    expected = copy.deepcopy(original)
    removals, pending = set(), []
    for path, item in candidates.items():
        if get(base, path) is not MISSING:
            continue
        current = get(original, path)
        if current is MISSING:
            continue
        old_values = [get(load(item['source']), path)] if 'source' in item else item['values']
        if any(equal(current, old) for old in old_values):
            parent = get(expected, path[:-1])
            del parent[path[-1]]
            removals.add(path)
            print(('  [would-remove] ' if args.check else '  [remove] ') + '.'.join(path))
        else:
            pending.append(item)
            print('  [conflict] preserved locally changed retired key: ' + '.'.join(path))
    if args.format == 'json':
        # Retire empty containers only along removed paths. Unrelated empty
        # objects and local siblings remain; current base can recreate a table.
        for path in removals:
            for length in range(len(path) - 1, 0, -1):
                parent_path = path[:length]
                if get(expected, parent_path) == {} and get(base, parent_path) is MISSING:
                    del get(expected, parent_path[:-1])[parent_path[-1]]
        overlay(expected, base, replace_tables=True)
        rendered = (original_text if exists and equal(original, expected) else
                    json.dumps(expected, ensure_ascii=False, indent=2) + '\n')
    else:
        stripped = remove_assignments(original_text, removals) if removals else original_text
        # Keep explicit headers; remove implicit parents lost with dotted keys.
        stripped_model = tomli.loads(stripped)
        for path in removals:
            for length in range(len(path) - 1, 0, -1):
                parent_path = path[:length]
                if get(expected, parent_path) == {} and get(stripped_model, parent_path) is MISSING:
                    del get(expected, parent_path[:-1])[parent_path[-1]]
        overlay(expected, base)
        if not exists:
            rendered = base_text
        else:
            with tempfile.TemporaryDirectory(prefix='dotfiles-toml-') as temp:
                b, t = Path(temp) / 'base', Path(temp) / 'target'
                b.write_text(base_text, encoding='utf-8')
                t.write_text(stripped, encoding='utf-8')
                rendered = subprocess.run(['awk', '-f', str(SCRIPTS / 'merge-toml.awk'), str(b), str(t)],
                                          check=True, capture_output=True, text=True).stdout
    if not equal(load(rendered), expected):
        raise ValueError('renderer cannot safely express merge; no config or snapshot written')
    changed = not exists or rendered != original_text or target.is_symlink()
    if args.check:
        print('  [drift] managed configuration differs' if changed else '  [ok] managed configuration in sync')
        return 1 if changed or pending else 0
    # Recheck inputs after rendering, before any persistent writes.
    if base_path.read_text(encoding='utf-8') != base_text or target.exists() != exists or (
            exists and target.read_text(encoding='utf-8') != original_text):
        raise ValueError('configuration changed during merge; retry')
    if (state_path.read_text(encoding='utf-8') if state_path.exists() else None) != state_text:
        raise ValueError('snapshot changed during merge; retry')
    if changed:
        mode = stat.S_IMODE(target.stat().st_mode) if exists else 0o600
        if exists:
            backup_root = Path(os.environ.get('DOTFILES_BACKUP', str(SCRIPTS.parents[3] / 'backup')))
            try:
                relative = target.relative_to(Path.home())
            except ValueError:
                relative = Path('external') / str(target).lstrip('/')
            backup = backup_root / relative
            if not backup.exists():
                backup.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(target, backup)
            atomic_write(Path(str(target) + '.pre-merge.bak'), original_text, mode)
        atomic_write(target, rendered, mode)
    new_state = json.dumps({'version': 1, 'target': identity, 'base_path': str(base_path),
                            'base': snapshot_base, 'pending': pending, 'migrations': sorted(completed)},
                           ensure_ascii=False, indent=2) + '\n'
    if new_state != state_text:
        atomic_write(state_path, new_state)
    print('  [ok] merged configuration and saved base snapshot' if changed else
          '  [ok] configuration unchanged; base snapshot up to date')
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        # TOML parser errors may contain source text; avoid printing values.
        message = ('invalid settings syntax; no config written'
                   if isinstance(error, (tomli.TOMLDecodeError, json.JSONDecodeError)) else str(error))
        print('  [error] ' + message, file=sys.stderr)
        sys.exit(1)
