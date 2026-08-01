#!/bin/bash
# install-manifest-skills.sh — skills-manifest.toml의 서드파티 스킬을 npx skills로 설치·갱신
# 네트워크가 필요하다. 실패해도 다른 설정에 영향이 없도록 항목별로 계속 진행한다.
# Usage: bash install-manifest-skills.sh

DOTFILES="$(cd "$(dirname "$0")/../../../../" && pwd)"
MANIFEST="$DOTFILES/config/ai/skills-manifest.toml"

if [ ! -f "$MANIFEST" ]; then
  echo "  [skip] skills-manifest.toml not found"
  exit 0
fi

# nvm으로 설치된 node는 비대화형 셸(ssh로 원격 apply 실행 등)에서 .bashrc/.zshrc가
# 소싱되지 않아 PATH에 안 잡힌다 — nvm이 있으면 명시적으로 로드한다.
export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh" >/dev/null 2>&1

if ! command -v npx >/dev/null 2>&1; then
  echo "  [warn] npx not found — third-party skills skipped"
  exit 0
fi

FAILED=0
CONFIG_ERRORS=0

# agent id → 설치 결과를 확인할 디렉토리.
# npx skills는 canonical 사본을 ~/.agents/skills/<name>에 두고, 그 경로를 직접 읽지 않는
# 도구에만 별도 심링크를 만든다. codex는 ~/.agents/skills가 표준 경로라 링크가 없다.
# 빈 문자열을 돌려주면 "모르는 id"라는 뜻이다.
agent_skill_dir() {
  case "$1" in
    claude-code) echo "$HOME/.claude/skills" ;;
    codex)       echo "$HOME/.agents/skills" ;;
    gemini-cli)  echo "$HOME/.gemini/skills" ;;
    cursor)      echo "$HOME/.cursor/skills" ;;
    amp)         echo "$HOME/.config/amp/skills" ;;
    antigravity) echo "$HOME/.antigravity/skills" ;;
    *)           echo "" ;;
  esac
}

# 설치 후 실제로 그 자리에 있는지 확인한다. skills 목록을 선언하지 않은 항목은
# 무엇이 설치될지 알 수 없으므로 건너뛴다.
verify_entry() {
  local alias="$1" skills="$2" agents="$3"
  local missing=0 a s dir
  [ -n "$skills" ] || return 0
  for a in $(echo "$agents" | tr ',' ' '); do
    dir="$(agent_skill_dir "$a")"
    [ -n "$dir" ] || continue
    for s in $(echo "$skills" | tr ',' ' '); do
      if [ ! -e "$dir/$s" ]; then
        echo "  [error] $alias: '$s' not found at $dir (agent=$a)"
        missing=1
      fi
    done
  done
  [ "$missing" -eq 0 ] && echo "  [ok] $alias verified on disk"
  return "$missing"
}

# manifest에서 (별칭|source|skills|agents) 추출
awk '
function emit() { if (src != "") print alias "|" src "|" skills "|" agents }
/^\[skills\./ {
  emit()
  alias = $0; sub(/^\[skills\./, "", alias); sub(/\][ \t]*$/, "", alias)
  src = ""; skills = ""; agents = ""
  next
}
/^[ \t]*source[ \t]*=/ { v = $0; sub(/^[^=]*=[ \t]*"/, "", v); sub(/"[ \t]*$/, "", v); src = v }
/^[ \t]*skills[ \t]*=/ { v = $0; sub(/^[^=]*=[ \t]*"/, "", v); sub(/"[ \t]*$/, "", v); skills = v }
/^[ \t]*agents[ \t]*=/ { v = $0; sub(/^[^=]*=[ \t]*"/, "", v); sub(/"[ \t]*$/, "", v); agents = v }
END { emit() }
' "$MANIFEST" > /tmp/skills-manifest-entries.$$

while IFS='|' read -r alias src skills agents; do
  [ -n "$src" ] || continue

  # agent ID를 먼저 검증한다 — npx skills는 모르는 ID를 에러 없이 조용히 무시하므로
  # (`-a __invalid__`로 확인) 오타가 나면 그 도구에만 스킬이 안 깔린 채 성공으로 보인다.
  bad_agent=false
  for a in $(echo "$agents" | tr ',' ' '); do
    if [ -z "$(agent_skill_dir "$a")" ]; then
      echo "  [error] $alias: unknown agent id '$a' — npx skills would silently ignore it"
      bad_agent=true
    fi
  done
  if $bad_agent; then
    echo "          known ids: claude-code, codex, gemini-cli, cursor, amp, antigravity"
    CONFIG_ERRORS=$((CONFIG_ERRORS + 1))
    continue
  fi

  extra_args=""
  for s in $(echo "$skills" | tr ',' ' '); do
    extra_args="$extra_args --skill $s"
  done
  for a in $(echo "$agents" | tr ',' ' '); do
    extra_args="$extra_args -a $a"
  done
  echo "  [skill:$alias] npx skills add $src$extra_args -g -y"
  if npx -y skills add "$src" $extra_args -g -y </dev/null; then
    echo "  [ok] $alias installed/updated"
    # 설치가 성공했다고 해서 원하는 곳에 깔렸다는 뜻은 아니다 — 경로를 직접 본다.
    verify_entry "$alias" "$skills" "$agents" || CONFIG_ERRORS=$((CONFIG_ERRORS + 1))
  else
    echo "  [fail] $alias — install failed (offline?), continuing"
    FAILED=$((FAILED + 1))
  fi
done < /tmp/skills-manifest-entries.$$
rm -f /tmp/skills-manifest-entries.$$

# 네트워크·설치 실패는 경고로 넘긴다 (오프라인 머신에서 apply 전체를 막지 않기 위해).
# 반면 설정 오류(잘못된 agent id, 설치 후에도 없는 스킬)는 사람이 고쳐야 하므로 실패로 알린다.
[ "$FAILED" -eq 0 ] || echo "  [warn] $FAILED manifest skill(s) failed to install"
if [ "$CONFIG_ERRORS" -ne 0 ]; then
  echo "  [error] $CONFIG_ERRORS manifest entry(ies) misconfigured — fix skills-manifest.toml"
  exit 1
fi
exit 0
