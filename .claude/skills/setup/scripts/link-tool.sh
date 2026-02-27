#!/bin/bash
# link-tool.sh — AI 도구별 심링크 생성
# Usage: bash link-tool.sh <claude|codex|gemini> [--unified|--separate]
#   --unified:  config/ai/AGENTS.md 하나로 모든 도구의 인스트럭션을 공유 (기본값)
#   --separate: 각 도구 폴더의 개별 인스트럭션 파일 사용
set -e

DOTFILES="$(cd "$(dirname "$0")/../../../../" && pwd)"
CONFIG="$DOTFILES/config"
BACKUP="$DOTFILES/backup"
TOOL="${1:?Usage: link-tool.sh <claude|codex|gemini> [--unified|--separate]}"
MODE="${2:---unified}"

backup_and_link() {
  local src="$1" dst="$2"
  local rel_path="${dst#$HOME/}"
  mkdir -p "$(dirname "$dst")"
  if [ -L "$dst" ]; then
    rm "$dst"
  elif [ -e "$dst" ]; then
    mkdir -p "$(dirname "$BACKUP/$rel_path")"
    cp -a "$dst" "$BACKUP/$rel_path"
    rm "$dst"
    echo "  [backup] $dst -> backup/$rel_path"
  fi
  ln -sf "$src" "$dst"
  echo "  [ok] $dst -> $src"
}

backup_and_link_dir() {
  local src="$1" dst="$2"
  local rel_path="${dst#$HOME/}"
  if [ -L "$dst" ]; then
    rm "$dst"
  elif [ -d "$dst" ]; then
    mkdir -p "$(dirname "$BACKUP/$rel_path")"
    cp -a "$dst" "$BACKUP/$rel_path"
    rm -rf "$dst"
    echo "  [backup] $dst -> backup/$rel_path"
  fi
  ln -sfn "$src" "$dst"
  echo "  [ok] $dst -> $src"
}

echo "--- $TOOL ---"

case "$TOOL" in
  claude)
    mkdir -p "$HOME/.claude"
    [ -f "$CONFIG/ai/claude/settings.json" ] && backup_and_link "$CONFIG/ai/claude/settings.json" "$HOME/.claude/settings.json"
    if [ "$MODE" = "--unified" ]; then
      [ -f "$CONFIG/ai/AGENTS.md" ] && backup_and_link "$CONFIG/ai/AGENTS.md" "$HOME/.claude/CLAUDE.md"
    else
      [ -f "$CONFIG/ai/claude/CLAUDE.md" ] && backup_and_link "$CONFIG/ai/claude/CLAUDE.md" "$HOME/.claude/CLAUDE.md"
    fi
    [ -d "$CONFIG/ai/claude/skills" ] && backup_and_link_dir "$CONFIG/ai/claude/skills" "$HOME/.claude/skills"
    [ -d "$CONFIG/ai/claude/agents" ] && backup_and_link_dir "$CONFIG/ai/claude/agents" "$HOME/.claude/agents"
    ;;
  codex)
    mkdir -p "$HOME/.codex"
    [ -f "$CONFIG/ai/codex/config.toml" ] && backup_and_link "$CONFIG/ai/codex/config.toml" "$HOME/.codex/config.toml"
    if [ "$MODE" = "--unified" ]; then
      [ -f "$CONFIG/ai/AGENTS.md" ] && backup_and_link "$CONFIG/ai/AGENTS.md" "$HOME/.codex/AGENTS.md"
    else
      [ -f "$CONFIG/ai/codex/AGENTS.md" ] && backup_and_link "$CONFIG/ai/codex/AGENTS.md" "$HOME/.codex/AGENTS.md"
    fi
    [ -d "$CONFIG/ai/codex/rules" ] && backup_and_link_dir "$CONFIG/ai/codex/rules" "$HOME/.codex/rules"
    ;;
  gemini)
    mkdir -p "$HOME/.gemini"
    [ -f "$CONFIG/ai/gemini/settings.json" ] && backup_and_link "$CONFIG/ai/gemini/settings.json" "$HOME/.gemini/settings.json"
    if [ "$MODE" = "--unified" ]; then
      [ -f "$CONFIG/ai/AGENTS.md" ] && backup_and_link "$CONFIG/ai/AGENTS.md" "$HOME/.gemini/GEMINI.md"
    else
      [ -f "$CONFIG/ai/gemini/GEMINI.md" ] && backup_and_link "$CONFIG/ai/gemini/GEMINI.md" "$HOME/.gemini/GEMINI.md"
    fi
    ;;
  *)
    echo "  [error] Unknown tool: $TOOL (expected claude, codex, or gemini)"
    exit 1
    ;;
esac
