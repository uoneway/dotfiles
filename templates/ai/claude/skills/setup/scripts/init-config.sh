#!/bin/bash
# init-config.sh — templates/ → config/ 초기 복사 (최초 1회)
set -e

DOTFILES="$(cd "$(dirname "$0")/../../../../../../" && pwd)"
CONFIG="$DOTFILES/config"
TEMPLATES="$DOTFILES/templates"

if [ -d "$CONFIG/ai" ] || [ -d "$CONFIG/shell" ]; then
  echo "[skip] config/ already exists. Skipping initial copy."
  exit 0
fi

echo "Copying templates/ → config/..."
mkdir -p "$CONFIG"

# AI 도구 설정
cp -r "$TEMPLATES/ai" "$CONFIG/ai"

# 셸 설정
cp -r "$TEMPLATES/shell" "$CONFIG/shell"

# config/ai/claude 내 setup, uninstall 스킬은 제외 (템플릿 전용)
rm -rf "$CONFIG/ai/claude/skills/setup"
rm -rf "$CONFIG/ai/claude/skills/uninstall"

echo "[ok] config/ initialized from templates/"
echo "Edit files in config/ to customize your setup."
