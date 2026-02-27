#!/bin/bash
# check-env.sh — 환경 감지 (OS, 셸, 설치된 도구)
# 구조화된 블록으로 출력하여 AI가 파싱하기 쉽게 함
set -e

DOTFILES="$(cd "$(dirname "$0")/../../../../" && pwd)"

# OS
case "$(uname -s)" in
  Darwin*) OS="macOS" ;;
  Linux*)  OS="Linux" ;;
  *)       OS="Unknown" ;;
esac

# Shell
case "$SHELL" in
  */zsh)  USER_SHELL="zsh" ;;
  */bash) USER_SHELL="bash" ;;
  *)      USER_SHELL="unknown" ;;
esac

# AI tools
HAS_CLAUDE=false; command -v claude &>/dev/null && HAS_CLAUDE=true
HAS_CODEX=false;  command -v codex  &>/dev/null && HAS_CODEX=true
HAS_GEMINI=false; command -v gemini &>/dev/null && HAS_GEMINI=true

# Oh My Zsh
HAS_OMZ=false; [ -d "$HOME/.oh-my-zsh" ] && HAS_OMZ=true

# nvm
HAS_NVM=false
[ -d "$HOME/.nvm" ] && HAS_NVM=true
[ -d "$NVM_DIR" ] 2>/dev/null && HAS_NVM=true

# config/ 존재 여부
HAS_CONFIG=false
[ -d "$DOTFILES/config/ai" ] || [ -d "$DOTFILES/config/shell" ] && HAS_CONFIG=true

# 출력
echo "=== ENVIRONMENT ==="
echo "os=$OS"
echo "shell=$USER_SHELL"
echo "dotfiles=$DOTFILES"
echo ""
echo "=== AI TOOLS ==="
echo "claude=$HAS_CLAUDE"
echo "codex=$HAS_CODEX"
echo "gemini=$HAS_GEMINI"
echo ""
echo "=== DEPENDENCIES ==="
echo "oh-my-zsh=$HAS_OMZ"
echo "nvm=$HAS_NVM"
echo ""
echo "=== STATE ==="
echo "config_exists=$HAS_CONFIG"
echo "first_run=$( [ "$HAS_CONFIG" = "true" ] && echo "false" || echo "true" )"
echo "=== END ==="
