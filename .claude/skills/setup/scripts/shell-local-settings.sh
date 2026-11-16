#!/bin/bash
# Shared by shell apply and verify. Inspect paths only; never read local secrets.
check_shell_local_settings() {
  local config="$1" home="$2" name shared target errors=0
  for name in local.zsh secrets.zsh; do
    shared="$config/terminal/zsh/zshrc.d/$name"
    target="$home/.zshrc.d/$name"
    if [ -e "$shared" ] || [ -L "$shared" ]; then
      echo "  [fail] $name is reserved for this machine; remove it from config/terminal/zsh/zshrc.d"
      errors=$((errors + 1))
    fi
    if [ -L "$target" ]; then
      echo "  [fail] $target must be a local regular file, not a symlink; restore it manually"
      errors=$((errors + 1))
    elif [ -e "$target" ] && [ ! -f "$target" ]; then
      echo "  [fail] $target must be a local regular file"
      errors=$((errors + 1))
    fi
  done
  [ "$errors" -eq 0 ]
}
