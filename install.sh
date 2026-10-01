#!/bin/bash
# Install programs without an AI CLI; use --setup to apply settings as well.
set -eu
INSTALL_ROOT="$(cd "$(dirname "$0")" && pwd)"
case "${1:-}" in
  --apps)
    shift
    exec bash "$INSTALL_ROOT/bin/dotfiles" install "$@" ;;
  --setup)
    shift
    exec bash "$INSTALL_ROOT/bin/dotfiles" apply "$@" ;;
esac
echo "=== dotfiles ==="
echo ""
echo "권장: Claude Code에서 /setup 실행"
echo "  cd ~/dotfiles && claude"
echo "  → /setup"
echo ""
echo "Claude Code 없이 수동 설치하려면:"
echo "  bash install.sh --apps                   # 앱/CLI 설치"
echo "  bash install.sh --apps --dry-run         # 설치 정책 확인"
echo "  bash install.sh --setup                  # 앱/CLI 설치 후 설정 적용"
echo "  개인 설정이 아직 없으면 .claude/skills/setup/scripts/init-config.sh로 준비하세요."
echo ""
