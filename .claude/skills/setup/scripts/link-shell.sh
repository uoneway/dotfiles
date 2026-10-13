#!/bin/bash
# link-shell.sh — 셸 설정 심링크 생성
# Usage: bash link-shell.sh [zsh]
set -e

DOTFILES="$(cd "$(dirname "$0")/../../../../" && pwd)"
CONFIG="$DOTFILES/config"
BACKUP="$DOTFILES/backup"
source "$(dirname "$0")/machine-config.sh"
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

if [ "$SHELL_TYPE" != "zsh" ]; then
  echo "  [error] Only zsh settings are managed" >&2
  exit 1
fi
if ! command -v zsh >/dev/null 2>&1; then
  echo "  [error] Install zsh before applying terminal settings" >&2
  exit 1
fi

if [ -f "$CONFIG/terminal/zsh/zshrc" ]; then
  backup_and_link "$CONFIG/terminal/zsh/zshrc" "$HOME/.zshrc"
  mkdir -p "$HOME/.zshrc.d"
  if [ -d "$CONFIG/terminal/zsh/zshrc.d" ]; then
    for f in "$CONFIG/terminal/zsh/zshrc.d"/*.zsh; do
      [ -f "$f" ] && backup_and_link "$f" "$HOME/.zshrc.d/$(basename "$f")"
    done
  fi
  # 이전 alias 파일의 관리 심링크만 정리한다. 로컬 실파일은 유지한다.
  if [ -L "$HOME/.zshrc.d/aliases.zsh" ]; then
    case "$(readlink "$HOME/.zshrc.d/aliases.zsh")" in
      "$CONFIG/terminal/zsh/zshrc.d/aliases.zsh") rm "$HOME/.zshrc.d/aliases.zsh" ;;
    esac
  fi
  # 머신별 추가 셸 설정은 machines.toml에서 선택한다. OS 파일은 zshrc가 자동 선택한다.
  local_addition="$(dotfiles_machine_extra "$(dotfiles_machine_name)" zsh_addition)" || exit 1
  addition_link="$HOME/.zshrc.d/machine-addition.zsh"
  if [ -n "$local_addition" ]; then
    addition_source="$CONFIG/terminal/zsh/additions/$local_addition"
    [ -f "$addition_source" ] || { echo "  [error] zsh addition not found: $addition_source" >&2; exit 1; }
    backup_and_link "$addition_source" "$addition_link"
  elif [ -L "$addition_link" ]; then
    case "$(readlink "$addition_link")" in
      "$CONFIG/terminal/zsh/additions/"*|"$CONFIG/shell/zshrc-additions/"*) rm "$addition_link" ;;
    esac
  fi
  # 로그인 셸이 zsh가 아니면(chsh 불가 서버 등) bashrc에 인터랙티브 전용 전환 블록 추가.
  # $- 가드로 비대화형(ssh 원격 명령 등)에는 절대 발동하지 않는다.
  if [ "$(basename "${SHELL:-}")" != "zsh" ] && command -v zsh >/dev/null 2>&1; then
    if ! grep -q 'dotfiles: exec zsh' "$HOME/.bashrc" 2>/dev/null; then
      cat >> "$HOME/.bashrc" <<'ZSHBLOCK'

# >>> dotfiles: exec zsh (로그인 셸 변경 불가 환경에서 zsh 사용, DOTFILES_NO_ZSH=1로 우회) >>>
case $- in *i*)
  if [ -z "${DOTFILES_NO_ZSH:-}" ] && command -v zsh >/dev/null 2>&1; then
    export SHELL="$(command -v zsh)"
    exec zsh
  fi
;; esac
# <<< dotfiles: exec zsh <<<
ZSHBLOCK
      echo "  [ok] ~/.bashrc에 zsh 전환 블록 추가 (인터랙티브 전용)"
    fi
  fi
else
  echo "  [skip] config/terminal/zsh/zshrc not found"
fi
