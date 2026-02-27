#!/bin/bash
# verify.sh — 설치 결과 검증
# Usage: bash verify.sh [--unified|--separate]
# 모든 심링크 상태를 확인하고 구조화된 결과를 출력
set -e

DOTFILES="$(cd "$(dirname "$0")/../../../../" && pwd)"
CONFIG="$DOTFILES/config"
MODE="${1:---unified}"
ERRORS=0

check_link() {
  local dst="$1" expected_src="$2" label="$3"
  if [ -L "$dst" ]; then
    local actual_src
    actual_src="$(readlink "$dst")"
    if [ "$actual_src" = "$expected_src" ]; then
      echo "  [ok] $label: $dst"
    else
      echo "  [fail] $label: $dst points to $actual_src (expected $expected_src)"
      ERRORS=$((ERRORS + 1))
    fi
  elif [ -e "$dst" ]; then
    echo "  [fail] $label: $dst exists but is not a symlink"
    ERRORS=$((ERRORS + 1))
  else
    echo "  [skip] $label: $dst does not exist"
  fi
}

check_file_exists() {
  local path="$1" label="$2"
  if [ -e "$path" ]; then
    echo "  [ok] $label: $path"
  else
    echo "  [fail] $label: $path not found"
    ERRORS=$((ERRORS + 1))
  fi
}

# Detect shell
case "$SHELL" in
  */zsh)  USER_SHELL="zsh" ;;
  */bash) USER_SHELL="bash" ;;
  *)      USER_SHELL="zsh" ;;
esac

echo "=== VERIFY (mode: ${MODE#--}) ==="
echo ""

# AI Tools
if command -v claude &>/dev/null || [ -d "$HOME/.claude" ]; then
  echo "--- claude ---"
  check_link "$HOME/.claude/settings.json" "$CONFIG/ai/claude/settings.json" "settings.json"
  if [ "$MODE" = "--unified" ]; then
    check_link "$HOME/.claude/CLAUDE.md" "$CONFIG/ai/AGENTS.md" "CLAUDE.md"
  else
    check_link "$HOME/.claude/CLAUDE.md" "$CONFIG/ai/claude/CLAUDE.md" "CLAUDE.md"
  fi
  check_link "$HOME/.claude/skills" "$CONFIG/ai/claude/skills" "skills/"
  check_link "$HOME/.claude/agents" "$CONFIG/ai/claude/agents" "agents/"
  echo ""
fi

if command -v codex &>/dev/null || [ -d "$HOME/.codex" ]; then
  echo "--- codex ---"
  check_link "$HOME/.codex/config.toml" "$CONFIG/ai/codex/config.toml" "config.toml"
  if [ "$MODE" = "--unified" ]; then
    check_link "$HOME/.codex/AGENTS.md" "$CONFIG/ai/AGENTS.md" "AGENTS.md"
  else
    check_link "$HOME/.codex/AGENTS.md" "$CONFIG/ai/codex/AGENTS.md" "AGENTS.md"
  fi
  check_link "$HOME/.codex/rules" "$CONFIG/ai/codex/rules" "rules/"
  echo ""
fi

if command -v gemini &>/dev/null || [ -d "$HOME/.gemini" ]; then
  echo "--- gemini ---"
  check_link "$HOME/.gemini/settings.json" "$CONFIG/ai/gemini/settings.json" "settings.json"
  if [ "$MODE" = "--unified" ]; then
    check_link "$HOME/.gemini/GEMINI.md" "$CONFIG/ai/AGENTS.md" "GEMINI.md"
  else
    check_link "$HOME/.gemini/GEMINI.md" "$CONFIG/ai/gemini/GEMINI.md" "GEMINI.md"
  fi
  echo ""
fi

# Shell
echo "--- shell ($USER_SHELL) ---"
if [ "$USER_SHELL" = "zsh" ]; then
  check_link "$HOME/.zshrc" "$CONFIG/shell/zshrc" "zshrc"
  if [ -d "$CONFIG/shell/zshrc.d" ]; then
    for f in "$CONFIG/shell/zshrc.d"/*.zsh; do
      [ -f "$f" ] && check_link "$HOME/.zshrc.d/$(basename "$f")" "$f" "zshrc.d/$(basename "$f")"
    done
  fi
else
  check_link "$HOME/.bashrc" "$CONFIG/shell/bashrc" "bashrc"
  if [ -d "$CONFIG/shell/bashrc.d" ]; then
    for f in "$CONFIG/shell/bashrc.d"/*.bash; do
      [ -f "$f" ] && check_link "$HOME/.bashrc.d/$(basename "$f")" "$f" "bashrc.d/$(basename "$f")"
    done
  fi
fi
echo ""

# Config integrity
echo "--- config integrity ---"
check_file_exists "$CONFIG/ai" "config/ai"
check_file_exists "$CONFIG/ai/AGENTS.md" "config/ai/AGENTS.md"
check_file_exists "$CONFIG/shell" "config/shell"
echo ""

# Summary
echo "=== RESULT ==="
if [ "$ERRORS" -eq 0 ]; then
  echo "All checks passed."
else
  echo "$ERRORS issue(s) found."
fi
echo "=== END ==="
