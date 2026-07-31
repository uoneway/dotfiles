# dotfiles 백로그 (2026-07-20 세션 핸드오프)

## 현재 상태 (완료된 것)

- **아키텍처 확정·구현 완료**: config/ 단일 소스 + 심링크(인스트럭션·스킬·agents) + 병합(settings.base.json/config.base.toml — base 키만 교체, 머신 상태 보존) + manifest(`npx skills`, mattpocock 22종)
- **멀티 머신 배포 가동 중**: `bin/dotfiles` CLI (apply/push/status/machines), machines.toml에 3대 등록 (link, doomfist-common, link-ubase — 전부 hub transport, shell,claude,codex)
- **4대 완전 동기화** (control 맥 + 원격 3대), Syncthing 완전 퇴역 (dotfiles-config 폴더 공유 해제, 잔재 정리)
- 일상 워크플로우: **config 편집 → 커밋 → `dotfiles push --all`**
- bash 로그인 서버는 bashrc의 인터랙티브 전용 exec zsh 블록으로 zsh 전환 (`DOTFILES_NO_ZSH=1` 우회)
- **4대 전부 nvm으로 Node 24(LTS) 통일** (2026-07-30) — doomfist-common(Node 없었음)·link-ubase(Node 18, EOL)에 nvm 설치 후 승급. `install-manifest-skills.sh`가 비대화형 ssh 셸에서 nvm을 못 찾던 버그도 같이 수정(`nvm.sh` 명시적 로드) — 두 머신 다 mattpocock 스킬 22개 정상 설치 확인

## `dotfiles status` 개선 (`feat/status-judgement` 브랜치, 2026-07-20)

방향: "데이터 나열"에서 **"판정을 대신하는"** status로. 원칙: 읽기 전용 유지, 기본 실행은 빠르게.

**1순위 — 완료 (커밋 `8d0d741`)**
- STATE 판정 자동화: control SHA와 비교 → `✓ synced` / `↓ behind N`(원격 fetch 후 `rev-list --count`) / `⚠ drift`(dirty) / `○ not bootstrapped` / `✗ unreachable(auth/timeout/dns/refused/unknown)`
- **APPLIED 추적**: `cmd_apply` 성공 시 `~/.local/state/dotfiles/applied`에 `<fw-sha> <cfg-sha> <epoch>` 기록, status가 repo SHA와 비교해 `✓ ok`/`⚠ stale`/`? never`로 표시
- 원격당 ssh 왕복 1회로 fw/cfg sha·dirty·behind·applied를 모두 수집 (heredoc + `bash -s`)
- printf 컬럼 정렬 테이블 출력
- 실제 3대(link, doomfist-common, link-ubase) 대상 검증 완료, "behind 1" 판정이 실제 미pull 커밋과 일치함을 직접 SHA 대조로 확인

**2순위 — 완료 (커밋 `35be0d8`)**
- `--json` 플래그 — 머신별 NDJSON 출력 (Phase 2 대시보드 데이터 소스, control 라인 포함)
- ssh `-o ControlMaster=auto -o ControlPersist=60s -o ControlPath=~/.ssh/dotfiles-cm/%C` — 반복 접속(push의 dirty-check/pull/apply, 반복 status 호출) 시 소켓 재사용
- APPLIED 컬럼에 마지막 apply 경과 시간 표시 (`_relative_time`: "just now"/"Nm ago"/"Nh ago"/"Nd ago")
- 주의: 2순위 구현 시점에 link.rtzr.ai 등 원격 3대가 네트워크(VPN 추정)로 unreachable이어서, 신규 필드(APPLIED_TS 파싱, JSON reachable-path)는 로컬 시뮬레이션/단위 테스트로만 검증됨 — 1순위 필드(behind/dirty/applied 매칭)는 이미 실제 3대로 검증된 로직을 그대로 재사용하므로 리스크 낮음. **다음 세션에서 원격 연결 복구 후 `dotfiles status`와 `dotfiles status --json` 한 번씩 실행해 실제 경로 재확인 권장**

**3순위 (opt-in, 미착수)**
- `--deep`: 원격 verify.sh 실행 요약
- manifest 스킬 설치 상태 가시화

**안 하기로 한 것**: 기본 동작에 verify 포함(느려짐), status에서 자동 복구(읽기/쓰기 분리 유지)

## 그 외 남은 태스크

| 항목 | 내용 | 시점 |
|---|---|---|
| Phase 2 대시보드 | localhost 웹, status --json 기반 머신 그리드 + push 버튼 + 로그 스트림 | 머신 늘어나 status 텍스트가 답답해질 때 |
| Phase 3 에디터 | config 파일 편집 UI | 우선순위 최하 |
| dotfiles.old 삭제 | link 서버의 옛 클론 (callabo-cli·move-to-docs는 회수 완료, 나머지는 대체됨) | 몇 주 안정 운영 후 |
| name-service _workspace 정리 | 작업 산출물(`_workspace/02_candidates-*.md`)이 config에 커밋돼 있음 | 정리 겸사 |
| 새 머신 추가 절차 | machines.toml 등록 → clone 2개 → `bin/dotfiles apply` (secrets.zsh 수동) — /sync-setup 참조 | 필요 시 |

## 알려진 한계 (문서화됨, 필요 시 개선)

- base에서 키를 **삭제**해도 라이브 파일에 잔존 (merge는 base에 없는 키 보존) — 삭제 시 라이브 수동 정리 필요. 빈발하면 "base가 소유한 객체는 통째 교체" 모드 검토
- 서드파티 스킬 버전이 머신별 설치 시점에 따라 다를 수 있음 (lockfile 없음)
- Gemini 기본 비활성 (Antigravity 전환 안정되면 재검토)
