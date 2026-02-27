#!/usr/bin/env bash
# config/ Git 상태 진단
set -euo pipefail

DOTFILES="${DOTFILES:-$HOME/dotfiles}"
CONFIG_DIR="$DOTFILES/config"

echo "=== GIT CONFIG ==="

if [[ ! -d "$CONFIG_DIR" ]]; then
  echo "config_exists=false"
  echo "=== END ==="
  exit 0
fi

echo "config_exists=true"

if [[ -d "$CONFIG_DIR/.git" ]]; then
  echo "has_git=true"
  cd "$CONFIG_DIR"
  BRANCH="$(git branch --show-current 2>/dev/null || echo none)"
  echo "branch=$BRANCH"
  REMOTE="$(git remote -v 2>/dev/null | head -1 || true)"
  if [[ -n "$REMOTE" ]]; then
    echo "has_remote=true"
    echo "remote=$REMOTE"
  else
    echo "has_remote=false"
  fi
  # 커밋되지 않은 변경사항
  DIRTY="$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
  echo "uncommitted=$DIRTY"
else
  echo "has_git=false"
fi

echo "=== END ==="
