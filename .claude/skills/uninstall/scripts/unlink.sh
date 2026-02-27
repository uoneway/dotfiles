#!/bin/bash
# unlink.sh — dotfiles 심링크 제거 및 backup/ 에서 원본 복원
# Usage: bash unlink.sh [all|claude|codex|gemini|shell] [--restore|--keep|--remove-only]
# --restore: backup/에서 원본 복원 (기본값)
# --keep: 심링크를 제거하고 config/ 파일 내용을 실제 파일로 복사
# --remove-only: 심링크만 제거
set -e

DOTFILES="$(cd "$(dirname "$0")/../../../../" && pwd)"
BACKUP="$DOTFILES/backup"
CONFIG="$DOTFILES/config"
TARGET="${1:-all}"
MODE="${2:---restore}"

unlink_file() {
  local dst="$1" label="$2" config_src="$3"
  local rel_path="${dst#$HOME/}"
  if [ -L "$dst" ]; then
    rm "$dst"
    case "$MODE" in
      --restore)
        if [ -e "$BACKUP/$rel_path" ]; then
          cp -a "$BACKUP/$rel_path" "$dst"
          echo "  [restored] $label: $dst (from backup/$rel_path)"
        else
          echo "  [removed] $label: $dst (no backup found)"
        fi
        ;;
      --keep)
        if [ -n "$config_src" ] && [ -e "$config_src" ]; then
          cp -a "$config_src" "$dst"
          echo "  [kept] $label: $dst (copied from config/)"
        else
          echo "  [removed] $label: $dst (no config source)"
        fi
        ;;
      --remove-only)
        echo "  [removed] $label: $dst"
        ;;
    esac
  else
    echo "  [skip] $label: $dst (not a symlink)"
  fi
}

unlink_dir() {
  local dst="$1" label="$2" config_src="$3"
  local rel_path="${dst#$HOME/}"
  if [ -L "$dst" ]; then
    rm "$dst"
    case "$MODE" in
      --restore)
        if [ -d "$BACKUP/$rel_path" ]; then
          cp -a "$BACKUP/$rel_path" "$dst"
          echo "  [restored] $label: $dst (from backup/$rel_path)"
        else
          echo "  [removed] $label: $dst (no backup found)"
        fi
        ;;
      --keep)
        if [ -n "$config_src" ] && [ -d "$config_src" ]; then
          cp -a "$config_src" "$dst"
          echo "  [kept] $label: $dst (copied from config/)"
        else
          echo "  [removed] $label: $dst (no config source)"
        fi
        ;;
      --remove-only)
        echo "  [removed] $label: $dst"
        ;;
    esac
  else
    echo "  [skip] $label: $dst (not a symlink)"
  fi
}

# Detect shell
case "$SHELL" in
  */zsh)  USER_SHELL="zsh" ;;
  */bash) USER_SHELL="bash" ;;
  *)      USER_SHELL="zsh" ;;
esac

echo "=== UNINSTALL (mode: $MODE) ==="
echo ""

# AI Tools (먼저 제거)
if [ "$TARGET" = "all" ] || [ "$TARGET" = "claude" ]; then
  echo "--- claude ---"
  unlink_file "$HOME/.claude/settings.json" "settings.json" "$CONFIG/ai/claude/settings.json"
  unlink_file "$HOME/.claude/CLAUDE.md" "CLAUDE.md" "$CONFIG/ai/CLAUDE.md"
  unlink_dir  "$HOME/.claude/skills" "skills/" "$CONFIG/ai/claude/skills"
  unlink_dir  "$HOME/.claude/agents" "agents/" "$CONFIG/ai/claude/agents"
  echo ""
fi

if [ "$TARGET" = "all" ] || [ "$TARGET" = "codex" ]; then
  echo "--- codex ---"
  unlink_file "$HOME/.codex/config.toml" "config.toml" "$CONFIG/ai/codex/config.toml"
  unlink_file "$HOME/.codex/AGENTS.md" "AGENTS.md" "$CONFIG/ai/AGENTS.md"
  unlink_dir  "$HOME/.codex/rules" "rules/" "$CONFIG/ai/codex/rules"
  echo ""
fi

if [ "$TARGET" = "all" ] || [ "$TARGET" = "gemini" ]; then
  echo "--- gemini ---"
  unlink_file "$HOME/.gemini/settings.json" "settings.json" "$CONFIG/ai/gemini/settings.json"
  unlink_file "$HOME/.gemini/GEMINI.md" "GEMINI.md" "$CONFIG/ai/GEMINI.md"
  echo ""
fi

# Shell (AI 이후 제거)
if [ "$TARGET" = "all" ] || [ "$TARGET" = "shell" ]; then
  echo "--- shell ($USER_SHELL) ---"
  if [ "$USER_SHELL" = "zsh" ]; then
    unlink_file "$HOME/.zshrc" "zshrc" "$CONFIG/shell/zshrc"
    if [ -d "$HOME/.zshrc.d" ]; then
      for f in "$HOME/.zshrc.d"/*.zsh; do
        [ -L "$f" ] && unlink_file "$f" "zshrc.d/$(basename "$f")" "$CONFIG/shell/zshrc.d/$(basename "$f")"
      done
    fi
  else
    unlink_file "$HOME/.bashrc" "bashrc" "$CONFIG/shell/bashrc"
    if [ -d "$HOME/.bashrc.d" ]; then
      for f in "$HOME/.bashrc.d"/*.bash; do
        [ -L "$f" ] && unlink_file "$f" "bashrc.d/$(basename "$f")" "$CONFIG/shell/bashrc.d/$(basename "$f")"
      done
    fi
  fi
  echo ""
fi

echo "=== DONE ==="
echo "config/ is preserved. Run /setup to re-install."
