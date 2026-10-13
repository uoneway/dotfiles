#!/bin/bash
# Merge Codex base keys; machine-specific keys remain in the live config.
set -e
DOTFILES="$(cd "$(dirname "$0")/../../../../" && pwd)"
exec bash "$(dirname "$0")/merge-toml.sh" \
  "$DOTFILES/config/ai/codex/config.base.toml" "$HOME/.codex/config.toml" "$@"
