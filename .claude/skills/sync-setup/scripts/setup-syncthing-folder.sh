#!/usr/bin/env bash
# Syncthing에 dotfiles-config 폴더를 등록하고 .stignore/.gitignore를 설정
# Usage: bash setup-syncthing-folder.sh [--with-git] [--remove-dotfiles]
set -euo pipefail

DOTFILES="${DOTFILES:-$HOME/dotfiles}"
CONFIG_DIR="$DOTFILES/config"
WITH_GIT=false
REMOVE_DOTFILES=false

for arg in "$@"; do
  case "$arg" in
    --with-git) WITH_GIT=true ;;
    --remove-dotfiles) REMOVE_DOTFILES=true ;;
  esac
done

echo "=== SYNCTHING FOLDER SETUP ==="

# ~/dotfiles 전체 폴더가 등록되어 있으면 제거 (--remove-dotfiles)
if $REMOVE_DOTFILES; then
  if syncthing cli config folders dotfiles path get &>/dev/null; then
    syncthing cli config folders dotfiles delete
    echo "[ok] removed folder: dotfiles (~/dotfiles 전체)"
  fi
fi

# dotfiles-config 폴더 등록
if syncthing cli config folders dotfiles-config path get &>/dev/null; then
  EXISTING_PATH="$(syncthing cli config folders dotfiles-config path get)"
  echo "[skip] dotfiles-config already registered: $EXISTING_PATH"
else
  syncthing cli config folders add --id dotfiles-config --label dotfiles-config --path "$CONFIG_DIR"
  echo "[ok] added folder: dotfiles-config -> $CONFIG_DIR"
fi

# .stignore (Git 병용 시 .git 제외)
if $WITH_GIT; then
  if [[ ! -f "$CONFIG_DIR/.stignore" ]] || ! grep -qxF '.git' "$CONFIG_DIR/.stignore" 2>/dev/null; then
    echo '.git' >> "$CONFIG_DIR/.stignore"
    echo "[ok] .stignore: added .git"
  else
    echo "[skip] .stignore: .git already present"
  fi
fi

# .gitignore (.stfolder 제외 — Syncthing 추적용 디렉토리)
if [[ ! -f "$CONFIG_DIR/.gitignore" ]] || ! grep -qxF '.stfolder' "$CONFIG_DIR/.gitignore" 2>/dev/null; then
  echo '.stfolder' >> "$CONFIG_DIR/.gitignore"
  echo "[ok] .gitignore: added .stfolder"
else
  echo "[skip] .gitignore: .stfolder already present"
fi

echo "=== DONE ==="
