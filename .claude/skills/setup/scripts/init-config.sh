#!/bin/bash
# init-config.sh — templates/ → config/ 초기 복사 (최초 1회)
set -e

DOTFILES="$(cd "$(dirname "$0")/../../../../" && pwd)"
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

# 머신 인벤토리 (멀티 머신 배포용)
[ -f "$TEMPLATES/machines.toml" ] && cp "$TEMPLATES/machines.toml" "$CONFIG/machines.toml"

# config/ai/claude 내 setup, uninstall 스킬은 제외 (템플릿 전용)
rm -rf "$CONFIG/ai/claude/skills/setup"
rm -rf "$CONFIG/ai/claude/skills/uninstall"

# Gemini는 기본 비활성 — 명시적으로 선택한 경우에만 setup이 템플릿을 복사한다
rm -rf "$CONFIG/ai/gemini"

echo "[ok] config/ initialized from templates/"
echo "Edit files in config/ to customize your setup."
