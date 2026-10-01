#!/bin/bash
# Per-machine additions are selected by machines.toml. The local marker stores
# only this machine's name; the selected files stay in the committed config repo.

dotfiles_machine_name() {
  if [ -n "${DOTFILES_MACHINE:-}" ]; then
    printf '%s\n' "$DOTFILES_MACHINE"
  elif [ -f "$HOME/.local/state/dotfiles/machine" ]; then
    cat "$HOME/.local/state/dotfiles/machine"
  fi
}

dotfiles_machine_extra() {
  local name="${1:-}" key="$2"
  python3 "$DOTFILES/.claude/skills/setup/scripts/machine-config.py" get "$name" "$key"
}
