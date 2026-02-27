#!/bin/bash
# verify.sh — 설치 결과 검증
# Usage: bash verify.sh [--unified|--separate] [--tools claude,codex,gemini]
# --tools를 생략하면 dotfiles 심링크가 걸린 도구만 검증
set -e

DOTFILES="$(cd "$(dirname "$0")/../../../../" && pwd)"
CONFIG="$DOTFILES/config"
MODE="--unified"
TOOLS=""
ERRORS=0

# 인자 파싱
while [ $# -gt 0 ]; do
  case "$1" in
    --unified|--separate) MODE="$1" ;;
    --tools) TOOLS="$2"; shift ;;
  esac
  shift
done

# 도구가 dotfiles에 의해 관리되는지 (심링크가 config/를 가리키는지)
is_managed() {
  local dst="$1"
  if [ -L "$dst" ]; then
    local target
    target="$(readlink "$dst")"
    case "$target" in
      *dotfiles/config/*) return 0 ;;
    esac
  fi
  return 1
}

# --tools가 없으면 심링크가 걸린 도구만 자동 감지
if [ -z "$TOOLS" ]; then
  detected=""
  is_managed "$HOME/.claude/settings.json" && detected="${detected}claude,"
  is_managed "$HOME/.codex/config.toml" && detected="${detected}codex,"
  is_managed "$HOME/.gemini/settings.json" && detected="${detected}gemini,"
  TOOLS="${detected%,}"
fi

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

echo "=== VERIFY (mode: ${MODE#--}, tools: ${TOOLS:-none}) ==="
echo ""

# AI Tools — 선택된 도구만 검증
if echo "$TOOLS" | grep -q "claude"; then
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

if echo "$TOOLS" | grep -q "codex"; then
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

if echo "$TOOLS" | grep -q "gemini"; then
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
