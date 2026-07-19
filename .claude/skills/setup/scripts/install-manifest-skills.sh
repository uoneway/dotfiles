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

if ! command -v npx >/dev/null 2>&1; then
  echo "  [warn] npx not found — third-party skills skipped"
  exit 0
fi

FAILED=0

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
  else
    echo "  [fail] $alias — install failed (offline?), continuing"
    FAILED=$((FAILED + 1))
  fi
done < /tmp/skills-manifest-entries.$$
rm -f /tmp/skills-manifest-entries.$$

[ "$FAILED" -eq 0 ] || echo "  [warn] $FAILED manifest skill(s) failed to install"
exit 0
