#!/bin/bash
# merge-claude-settings.sh — settings.base.json의 관리 키를 ~/.claude/settings.json에 병합
#
# 병합 규칙: base에 정의된 키만 교체한다 (object는 재귀 병합, 배열·스칼라는 통째 교체).
# base에 없는 키(hooks, permissions.additionalDirectories 등 머신 로컬 항목)는 보존한다.
#
# Usage: bash merge-claude-settings.sh [--check]
#   --check: 파일을 쓰지 않고 관리 키의 드리프트만 보고 (드리프트 시 exit 1)
set -e

DOTFILES="$(cd "$(dirname "$0")/../../../../" && pwd)"
BASE="$DOTFILES/config/ai/claude/settings.base.json"
TARGET="$HOME/.claude/settings.json"
CHECK=false
[ "$1" = "--check" ] && CHECK=true

if [ ! -f "$BASE" ]; then
  echo "  [error] settings.base.json not found: $BASE"
  exit 1
fi

mkdir -p "$HOME/.claude"

# 과거 설치에서 settings.json이 심링크였다면 실파일로 전환한다.
# (심링크를 통해 Claude Code가 머신 상태를 쓰면 config repo가 오염됨)
if [ -L "$TARGET" ]; then
  link_src="$(readlink "$TARGET")"
  rm "$TARGET"
  [ -f "$link_src" ] && cp "$link_src" "$TARGET"
  echo "  [ok] Converted symlink to real file: $TARGET"
fi

# 첫 설치: base를 그대로 복사
if [ ! -f "$TARGET" ]; then
  if $CHECK; then
    echo "  [drift] $TARGET does not exist"
    exit 1
  fi
  cp "$BASE" "$TARGET"
  echo "  [ok] Created $TARGET from settings.base.json"
  exit 0
fi

# 최초 병합 전 원본을 dotfiles/backup/에 보존 (홈 디렉토리 구조 미러링, 1회만)
if ! $CHECK; then
  BACKUP="$DOTFILES/backup"
  rel="${TARGET#$HOME/}"
  if [ ! -e "$BACKUP/$rel" ]; then
    mkdir -p "$(dirname "$BACKUP/$rel")"
    cp -a "$TARGET" "$BACKUP/$rel"
    echo "  [backup] $TARGET -> backup/$rel"
  fi
fi

MODE="write"
$CHECK && MODE="check"

python3 - "$BASE" "$TARGET" "$MODE" <<'PYEOF'
import difflib
import json
import os
import shutil
import sys

base_path, target_path, mode = sys.argv[1], sys.argv[2], sys.argv[3]

def merge(base, target):
    """base 키가 이긴다. object는 재귀 병합, 배열·스칼라는 base로 통째 교체."""
    if isinstance(base, dict) and isinstance(target, dict):
        out = dict(target)
        for key, value in base.items():
            out[key] = merge(value, target[key]) if key in target else value
        return out
    return base

def expand_marketplace_paths(cfg):
    """extraKnownMarketplaces[].source.path의 `~`를 절대 경로로 펼친다.

    Claude Code는 이 필드의 `~`를 확장하지 않고 cwd 기준 상대 경로로 해석한다
    (예: cwd가 /home/x/proj면 /home/x/proj/~/dotfiles/... 를 찾다가 실패).
    base에는 머신 무관하게 `~/...`로 적어두고, 병합 시점에 그 머신의 HOME으로 펼친다.
    settings.json은 동기화 대상이 아닌 로컬 실파일이므로 절대 경로가 들어가도 안전하다.
    """
    for entry in (cfg.get("extraKnownMarketplaces") or {}).values():
        source = entry.get("source") if isinstance(entry, dict) else None
        if isinstance(source, dict) and isinstance(source.get("path"), str):
            source["path"] = os.path.expanduser(source["path"])

with open(base_path) as f:
    base = json.load(f)
with open(target_path) as f:
    target = json.load(f)

expand_marketplace_paths(base)

merged = merge(base, target)

if merged == target:
    print("  [ok] settings.json already in sync with base")
    sys.exit(0)

if mode == "check":
    print("  [drift] managed keys differ from base:")
    before = json.dumps(target, indent=2, ensure_ascii=False).splitlines()
    after = json.dumps(merged, indent=2, ensure_ascii=False).splitlines()
    for line in list(difflib.unified_diff(before, after, lineterm=""))[2:22]:
        print("    " + line)
    sys.exit(1)

shutil.copy2(target_path, target_path + ".pre-merge.bak")
with open(target_path, "w") as f:
    json.dump(merged, f, indent=2, ensure_ascii=False)
    f.write("\n")
print("  [ok] Merged base into " + target_path
      + " (machine-local keys preserved; backup: settings.json.pre-merge.bak)")
PYEOF
