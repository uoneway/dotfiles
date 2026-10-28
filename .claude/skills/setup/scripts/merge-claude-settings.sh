#!/bin/bash
# Merge shared JSON keys and safely retire unchanged previously managed values.
# Usage: merge-claude-settings.sh [--check]
set -e
DOTFILES="$(cd "$(dirname "$0")/../../../../" && pwd)"
exec python3 "$(dirname "$0")/merge-settings.py" \
  "$DOTFILES/config/ai/claude/settings.base.json" "$HOME/.claude/settings.json" \
  --format json --claude-marketplace-root "$DOTFILES" "$@"
