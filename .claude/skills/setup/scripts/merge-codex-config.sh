#!/bin/bash
# merge-codex-config.sh — config.base.toml의 관리 키를 ~/.codex/config.toml에 병합
#
# 병합 규칙: base에 정의된 (섹션, 키)만 교체·추가하고, 그 외 모든 내용
# ([projects.*], [hooks.state.*], [plugins.*], [mcp_servers.*] 등 머신 상태)은 보존한다.
#
# Usage: bash merge-codex-config.sh [--check]
#   --check: 파일을 쓰지 않고 관리 키의 드리프트만 보고 (드리프트 시 exit 1)
set -e

DOTFILES="$(cd "$(dirname "$0")/../../../../" && pwd)"
BASE="$DOTFILES/config/ai/codex/config.base.toml"
TARGET="$HOME/.codex/config.toml"
CHECK=false
[ "$1" = "--check" ] && CHECK=true

if [ ! -f "$BASE" ]; then
  echo "  [error] config.base.toml not found: $BASE"
  exit 1
fi

mkdir -p "$HOME/.codex"

# 과거 설치에서 config.toml이 심링크였다면 실파일로 전환한다.
# (심링크를 통해 codex가 머신 상태를 쓰면 config repo가 오염됨)
if [ -L "$TARGET" ]; then
  link_src="$(readlink "$TARGET")"
  rm "$TARGET"
  [ -f "$link_src" ] && cp "$link_src" "$TARGET"
  echo "  [ok] Converted symlink to real file: $TARGET"
fi

# 첫 설치: base를 그대로 복사
if [ ! -f "$TARGET" ]; then
  if $CHECK; then
    echo "  [drift] $TARGET does not exist"
    exit 1
  fi
  cp "$BASE" "$TARGET"
  echo "  [ok] Created $TARGET from config.base.toml"
  exit 0
fi

# 최초 병합 전 원본을 dotfiles/backup/에 보존 (홈 디렉토리 구조 미러링, 1회만)
if ! $CHECK; then
  BACKUP="$DOTFILES/backup"
  rel="${TARGET#$HOME/}"
  if [ ! -e "$BACKUP/$rel" ]; then
    mkdir -p "$(dirname "$BACKUP/$rel")"
    cp -a "$TARGET" "$BACKUP/$rel"
    echo "  [backup] $TARGET -> backup/$rel"
  fi
fi

MERGED="$(mktemp)"
trap 'rm -f "$MERGED"' EXIT

awk '
function trimkey(s,    eq, k) {
  eq = index(s, "=")
  k = substr(s, 1, eq - 1)
  gsub(/^[ \t]+|[ \t]+$/, "", k)
  return k
}
function flush_sec(sec,    n, i, arr, k) {
  n = split(basekeys[sec], arr, SUBSEP)
  for (i = 2; i <= n; i++) {
    k = arr[i]
    if (!((sec SUBSEP k) in emitted)) {
      print baseval[sec SUBSEP k]
      emitted[sec SUBSEP k] = 1
    }
  }
}
BEGIN {
  KEYRE = "^[ \t]*(\"[^\"]*\"|[A-Za-z0-9_-]+(\\.[A-Za-z0-9_-]+)*)[ \t]*="
  sec = ""
  cursec = ""
}
# 1-pass: base 파일 — 관리 대상 (섹션, 키) 수집
FNR == NR {
  if ($0 ~ /^\[[^]]+\][ \t]*$/) {
    sec = $0; sub(/^\[/, "", sec); sub(/\][ \t]*$/, "", sec)
    if (!(sec in bsec)) { bsec[sec] = 1; bsecs[++nb] = sec }
    next
  }
  if ($0 ~ KEYRE) {
    k = trimkey($0)
    baseval[sec SUBSEP k] = $0
    basekeys[sec] = basekeys[sec] SUBSEP k
    if (sec != "" && !(sec in bsec)) { bsec[sec] = 1; bsecs[++nb] = sec }
  }
  next
}
# 2-pass: target 파일 — base 키만 교체, 나머지 통과
{
  if ($0 ~ /^\[[^]]+\][ \t]*$/) {
    flush_sec(cursec)                      # 섹션을 떠나기 전, base에만 있는 키를 섹션 끝에 추가
    while (nblank > 0) { print ""; nblank-- }
    cursec = $0; sub(/^\[/, "", cursec); sub(/\][ \t]*$/, "", cursec)
    tsec[cursec] = 1
    print
    next
  }
  if ($0 ~ /^[ \t]*$/) { nblank++; next }  # 빈 줄은 보류 (섹션 끝 추가 키가 빈 줄 앞에 오도록)
  while (nblank > 0) { print ""; nblank-- }
  if ($0 ~ KEYRE) {
    k = trimkey($0)
    if ((cursec SUBSEP k) in baseval) {
      print baseval[cursec SUBSEP k]
      emitted[cursec SUBSEP k] = 1
      next
    }
  }
  print
}
END {
  flush_sec(cursec)
  for (i = 1; i <= nb; i++) {              # target에 아예 없는 base 섹션은 통째로 추가
    sec = bsecs[i]
    if (sec == "" || (sec in tsec)) continue
    print ""
    print "[" sec "]"
    flush_sec(sec)
  }
}
' "$BASE" "$TARGET" > "$MERGED"

if cmp -s "$MERGED" "$TARGET"; then
  echo "  [ok] config.toml already in sync with base"
  exit 0
fi

if $CHECK; then
  echo "  [drift] managed keys differ from base:"
  diff "$TARGET" "$MERGED" | sed 's/^/    /'
  exit 1
fi

cp "$TARGET" "${TARGET}.pre-merge.bak"
mv "$MERGED" "$TARGET"
trap - EXIT
echo "  [ok] Merged base into $TARGET (machine state preserved; backup: config.toml.pre-merge.bak)"
