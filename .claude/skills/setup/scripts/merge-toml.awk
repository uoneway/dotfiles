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
FILENAME == ARGV[1] {
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
  if ($0 ~ /^[ \t]*\[\[/) {
    flush_sec(cursec)
    while (nblank > 0) { print ""; nblank-- }
    cursec = "@array:" ++array_index     # unmanaged array-of-table entries
    print
    next
  }
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
