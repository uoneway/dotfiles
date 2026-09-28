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
  local name="${1:-}" key="$2" file="$CONFIG/machines.toml" value
  [ -n "$name" ] || return 0
  case "$name" in
    *[!A-Za-z0-9._-]* ) echo "[error] invalid machine name: $name" >&2; return 1 ;;
  esac
  [ -f "$file" ] || { echo "[error] machines.toml not found" >&2; return 1; }

  value="$(awk -v name="$name" -v key="$key" '
    /^\[machines\.[A-Za-z0-9._-]+\][[:space:]]*$/ {
      current = $0
      sub(/^\[machines\./, "", current)
      sub(/\][[:space:]]*$/, "", current)
      if (current == name) found = 1
      next
    }
    current == name && $0 ~ "^[[:space:]]*" key "[[:space:]]*=" {
      value = $0
      sub(/^[^=]*=[[:space:]]*"/, "", value)
      sub(/"[[:space:]]*$/, "", value)
      print value
      exit
    }
    END { if (!found) exit 2 }
  ' "$file")" || { echo "[error] unknown machine: $name" >&2; return 1; }
  case "$value" in
    "" ) ;;
    *[!A-Za-z0-9._-]* ) echo "[error] invalid $key for $name: $value" >&2; return 1 ;;
  esac
  printf '%s\n' "$value"
}
