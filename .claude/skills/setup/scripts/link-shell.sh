#!/bin/bash
# link-shell.sh — 셸 설정 심링크 생성
# Usage: bash link-shell.sh <zsh|bash>
set -e

DOTFILES="$(cd "$(dirname "$0")/../../../../../../" && pwd)"
CONFIG="$DOTFILES/config"
BACKUP="$DOTFILES/backup"
SHELL_TYPE="${1:-zsh}"

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

echo "--- shell ($SHELL_TYPE) ---"

if [ "$SHELL_TYPE" = "zsh" ]; then
  if [ -f "$CONFIG/shell/zshrc" ]; then
    backup_and_link "$CONFIG/shell/zshrc" "$HOME/.zshrc"
    mkdir -p "$HOME/.zshrc.d"
    if [ -d "$CONFIG/shell/zshrc.d" ]; then
      for f in "$CONFIG/shell/zshrc.d"/*.zsh; do
        [ -f "$f" ] && backup_and_link "$f" "$HOME/.zshrc.d/$(basename "$f")"
      done
    fi
  else
    echo "  [skip] config/shell/zshrc not found"
  fi
elif [ "$SHELL_TYPE" = "bash" ]; then
  if [ -f "$CONFIG/shell/bashrc" ]; then
    backup_and_link "$CONFIG/shell/bashrc" "$HOME/.bashrc"
    mkdir -p "$HOME/.bashrc.d"
    if [ -d "$CONFIG/shell/bashrc.d" ]; then
      for f in "$CONFIG/shell/bashrc.d"/*.bash; do
        [ -f "$f" ] && backup_and_link "$f" "$HOME/.bashrc.d/$(basename "$f")"
      done
    fi
  else
    echo "  [skip] config/shell/bashrc not found"
  fi
else
  echo "  [error] Unknown shell: $SHELL_TYPE (expected zsh or bash)"
  exit 1
fi
