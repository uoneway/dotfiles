#!/usr/bin/env bash
# Syncthing 상태 진단 — 설치, 실행, 자동시작, 폴더, Device ID를 구조화 출력
set -euo pipefail

DOTFILES="${DOTFILES:-$HOME/dotfiles}"

echo "=== SYNCTHING ==="

# 설치 여부
if command -v syncthing &>/dev/null; then
  echo "installed=true"
  echo "version=$(syncthing --version 2>/dev/null | head -1)"
  # 실행 경로로 설치 방식 판별
  ST_PATH="$(command -v syncthing)"
  if [[ "$ST_PATH" == *"/opt/homebrew/"* ]] || [[ "$ST_PATH" == *"/usr/local/"* ]]; then
    echo "install_method=brew"
  elif [[ "$ST_PATH" == *"/Applications/"* ]]; then
    echo "install_method=app"
  else
    echo "install_method=system"
  fi
else
  echo "installed=false"
  echo "=== END ==="
  exit 0
fi

# 실행 여부 + 실행 방법
if pgrep -x syncthing &>/dev/null; then
  echo "running=true"
  RUN_CMD="$(ps -p "$(pgrep -x syncthing | head -1)" -o comm= 2>/dev/null || true)"
  if [[ "$RUN_CMD" == *"Applications/Syncthing.app"* ]]; then
    echo "run_method=app"
  else
    echo "run_method=other"
  fi
else
  echo "running=false"
  echo "run_method=none"
fi

# 자동 시작 등록 여부
if [[ "$(uname)" == "Darwin" ]]; then
  BREW_STATUS="$(brew services list 2>/dev/null | grep syncthing | awk '{print $2}' || true)"
  if [[ -n "$BREW_STATUS" && "$BREW_STATUS" != "none" ]]; then
    echo "autostart=brew_services"
    echo "autostart_status=$BREW_STATUS"
  elif pgrep -x syncthing &>/dev/null; then
    # brew에 없지만 실행 중 → 앱이 자체 관리 중일 가능성
    echo "autostart=app_or_manual"
  else
    echo "autostart=none"
  fi
else
  # Linux
  if systemctl --user is-enabled syncthing.service &>/dev/null; then
    echo "autostart=systemd"
    echo "autostart_status=$(systemctl --user is-active syncthing.service 2>/dev/null || echo unknown)"
  else
    echo "autostart=none"
  fi
fi

# 등록된 폴더
echo "--- folders ---"
if syncthing cli config folders list &>/dev/null; then
  for FOLDER_ID in $(syncthing cli config folders list 2>/dev/null); do
    FOLDER_PATH="$(syncthing cli config folders "$FOLDER_ID" path get 2>/dev/null || echo unknown)"
    echo "folder=$FOLDER_ID|$FOLDER_PATH"
  done
else
  echo "folders=unavailable"
fi

# Device ID
echo "--- device ---"
DEVICE_ID="$(syncthing cli show system 2>/dev/null | grep myID | sed 's/.*"myID": "\(.*\)".*/\1/' || true)"
if [[ -z "$DEVICE_ID" ]]; then
  # fallback: HTTP 헤더에서 추출
  DEVICE_ID="$(curl -s -o /dev/null -D - http://localhost:8384 2>/dev/null | grep X-Syncthing-Id | awk '{print $2}' | tr -d '\r' || true)"
fi
if [[ -n "$DEVICE_ID" ]]; then
  echo "device_id=$DEVICE_ID"
else
  echo "device_id=unavailable"
fi

echo "=== END ==="
