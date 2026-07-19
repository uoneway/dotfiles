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

# 병합 방식 파일(claude settings.json, codex config.toml)은 심링크가 아닌 실파일.
# --restore일 때만 backup 원본으로 되돌리고, 그 외에는 그대로 둔다 (이미 자체 완결 파일).
unlink_merged() {
  local dst="$1" label="$2"
  local rel_path="${dst#$HOME/}"
  if [ -L "$dst" ]; then
    # 구버전 설치(심링크)였다면 파일 취급으로 위임
    unlink_file "$dst" "$label" ""
    return
  fi
  if [ "$MODE" = "--restore" ] && [ -e "$BACKUP/$rel_path" ]; then
    cp -a "$BACKUP/$rel_path" "$dst"
    echo "  [restored] $label: $dst (from backup/$rel_path)"
  else
    echo "  [kept] $label: $dst (merged file, left as-is)"
  fi
}

# per-skill 심링크 제거: config/를 가리키는 링크만 지우고 나머지(서드파티 등)는 보존
unlink_skills() {
  local dst="$1" label="$2"
  local rel_path="${dst#$HOME/}"
  if [ -L "$dst" ]; then
    # 구버전 설치(디렉토리 통째 심링크)
    unlink_dir "$dst" "$label" ""
    return
  fi
  [ -d "$dst" ] || { echo "  [skip] $label: $dst (not found)"; return; }
  local link tgt n=0
  for link in "$dst"/*; do
    [ -L "$link" ] || continue
    tgt="$(readlink "$link")"
    case "$tgt" in
      "$CONFIG"/*) rm "$link"; n=$((n+1)) ;;
    esac
  done
  echo "  [removed] $label: $n config-managed skill link(s) from $dst"
  if [ "$MODE" = "--restore" ] && [ -d "$BACKUP/$rel_path" ]; then
    cp -a "$BACKUP/$rel_path/." "$dst/" 2>/dev/null || true
    echo "  [restored] $label: backup contents copied back"
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
  unlink_merged "$HOME/.claude/settings.json" "settings.json"
  unlink_file "$HOME/.claude/CLAUDE.md" "CLAUDE.md" "$CONFIG/ai/AGENTS.md"
  unlink_file "$HOME/.claude/statusline-command.sh" "statusline-command.sh" "$CONFIG/ai/claude/statusline-command.sh"
  unlink_skills "$HOME/.claude/skills" "skills/"
  unlink_dir  "$HOME/.claude/agents" "agents/" "$CONFIG/ai/claude/agents"
  echo ""
fi

if [ "$TARGET" = "all" ] || [ "$TARGET" = "codex" ]; then
  echo "--- codex ---"
  unlink_merged "$HOME/.codex/config.toml" "config.toml"
  unlink_file "$HOME/.codex/AGENTS.md" "AGENTS.md" "$CONFIG/ai/AGENTS.md"
  unlink_dir  "$HOME/.codex/rules" "rules/" "$CONFIG/ai/codex/rules"
  unlink_skills "$HOME/.codex/skills" "skills/"
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
