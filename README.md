# dotfiles

AI 코딩 도구(Claude Code, Codex CLI)와 셸(zsh/bash) 설정을 한 곳에서 관리하고, 여러 머신에 배포합니다.

## Why dotfiles

AI 코딩 도구마다 설정 파일 위치가 다릅니다. 글로벌 인스트럭션을 바꾸려면 `~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md`를 각각 열어서 같은 내용을 반복 수정해야 합니다. 셸 설정은 머신·OS마다 미묘하게 달라지고, 스킬은 도구마다 따로 설치해야 합니다.

이 프로젝트는 **모든 설정을 `config/` 한 폴더에 모으고, 각 도구의 원래 위치에 연결**합니다:

- **인스트럭션 (AGENTS.md)** — 파일 하나를 심링크로 모든 도구에 공유
- **스킬 (SKILL.md)** — 공용 스킬은 한 벌만 두고 per-skill 심링크로 각 도구에 배포. 서드파티 스킬은 manifest 선언 + `npx skills`로 설치
- **설정 (settings.json / config.toml)** — 심링크가 아닌 **병합**: 도구가 런타임에 머신 상태를 쓰는 파일이라, 내가 관리하는 base 키만 교체하고 나머지는 보존
- **셸 (zshrc)** — feature-detection(guard) 기반 공통 설정 + OS별 파일 + 머신 로컬 레이어(local.zsh/secrets.zsh, 동기화 제외)

여러 머신 배포는 **제어 머신 모델**입니다: 한 머신에서 편집·커밋하면 `dotfiles push`가 등록된 머신들에 git으로 배포하고 적용까지 실행합니다.

## Quick Start

```bash
git clone https://github.com/<username>/dotfiles ~/dotfiles
cd ~/dotfiles
claude
→ /setup
```

Claude Code 없이(또는 원격 머신에서):

```bash
git clone <framework-repo> ~/dotfiles
git clone <config-repo> ~/dotfiles/config     # 개인 설정 (private repo)
bash ~/dotfiles/bin/dotfiles apply
```

## `/setup` Does

`/setup` skill이 환경을 분석하고 질문 몇 개 후 자동으로 설정합니다.

**설치한 것을 되돌릴 수 있나요?**
기존 설정 파일은 `dotfiles/backup/`에 홈 디렉토리 구조 그대로 보존됩니다. 병합 방식 파일(settings.json, config.toml)은 원본이 파일로 남고 base 키만 갱신되므로 안전합니다. 되돌리려면 `/uninstall`을 실행하세요.

## 동기화 범위 — 무엇이 머신 간 공유되고, 무엇이 로컬에 남는가

원칙: **내 의도(취향·정책)는 동기화, 머신 상태(런타임 기록·자격증명·머신 경로)는 로컬.**
설정 파일 하나에 둘이 섞여 있는 경우(settings.json, config.toml)는 병합 방식으로 키 단위 분리한다.

### Claude Code (`~/.claude/`)

| 항목 | 동기화 | 방식 / 이유 |
|---|:---:|---|
| `CLAUDE.md` (글로벌 인스트럭션) | ✅ | 심링크 → `config/ai/AGENTS.md` (Codex와 공유) |
| `settings.json` 중 base 키 — permissions(allow/deny/ask), model, effortLevel, language, theme, statusLine, skillOverrides, env, 알림 설정 | ✅ | **병합** — `settings.base.json`의 키만 교체 |
| 플러그인 (`enabledPlugins`, `extraKnownMarketplaces`) | ✅ | 선언이 base로 동기화 → 각 머신이 자동 설치 |
| `skills/` (자작 스킬) | ✅ | per-skill 심링크 (공용 `ai/skills/` + Claude 전용) |
| `agents/` (서브에이전트) | ✅ | 심링크 |
| `statusline-command.sh` | ✅ | 심링크 |
| `keybindings.json`, `output-styles/` | ✅* | config에 두면 자동 링크 (현재 미사용) |
| `commands/` (커스텀 슬래시 커맨드) | ✅* | config에 두면 자동 링크 (현재 미사용 — 신규 작성은 skills 권장, commands는 구 방식) |
| `settings.json` 중 `hooks` | ❌ | 머신별 경로 의존 (훅 스크립트 위치가 머신마다 다름) |
| `settings.json` 중 `permissions.additionalDirectories` | ❌ | 머신별 경로 |
| `settings.local.json` | ❌ | 이름 그대로 머신 로컬 오버라이드 |
| `~/.claude.json` | ❌ | OAuth 세션·MCP 서버 등록·프로젝트 신뢰 상태 — 런타임 상태, 도구가 자동 관리 |
| `history.jsonl`, `projects/`, `sessions/`, plugins 캐시 | ❌ | 런타임 상태 |

### Codex CLI (`~/.codex/`)

| 항목 | 동기화 | 방식 / 이유 |
|---|:---:|---|
| `AGENTS.md` (글로벌 인스트럭션) | ✅ | 심링크 → `config/ai/AGENTS.md` (Claude와 공유) |
| `config.toml` 중 base 키 — model, model_verbosity, model_reasoning_effort, approval_policy, sandbox_mode, web_search, personality, commit_attribution, `[tui]`, `[features]`, network_access | ✅ | **병합** — `config.base.toml`의 키만 교체 |
| `rules/` (실행 정책) | ✅ | 심링크 |
| `skills/` (자작 스킬) | ✅ | per-skill 심링크 (공용 `ai/skills/` + Codex 전용) |
| `~/.agents/skills/` (서드파티 스킬) | ✅ | `skills-manifest.toml` 선언 → `npx skills`가 설치·갱신 |
| `prompts/` (커스텀 프롬프트) | ✅* | config에 두면 자동 링크 (현재 미사용) |
| `config.toml` 중 `[projects]` (신뢰 목록) | ❌ | 머신별 상태 — 머신마다 존재하는 프로젝트가 다름 |
| `config.toml` 중 `[mcp_servers]` | ❌ | 명령 경로가 머신 의존 (npx 기반 서버라면 base에 올려 동기화 가능) |
| `config.toml` 중 `[hooks.state]`, `[marketplaces]`, `[plugins]`, `[desktop]`, `notify`, `[notice]` | ❌ | 런타임 상태·머신 경로 |
| `auth.json` | ❌ | **자격증명 — 절대 동기화 금지** |
| `history.jsonl`, `log/`, sessions, memories | ❌ | 런타임 상태 |
| `<profile>.config.toml` (프로파일) | 후보 | 현재 미사용 — 쓰게 되면 base 패턴으로 추가 |

*✅\* = 지원되지만 현재 config에 없음 — 파일을 config에 추가하는 순간부터 동기화됨.*

### 셸 (`~/.zshrc`)

| 항목 | 동기화 | 방식 |
|---|:---:|---|
| `zshrc` (guard 기반 공통), `zshrc.d/{macos,linux}.zsh` | ✅ | 심링크 |
| `zshrc.d/local.zsh` (머신 전용 설정) | ❌ | 의도적 로컬 실파일 |
| `zshrc.d/secrets.zsh` (API 키·토큰) | ❌ | **절대 동기화 금지** — push 전 secret 스캔이 이중 방어 |

Gemini CLI는 템플릿만 제공하며 기본 비활성입니다 (Antigravity 전환이 안정되면 재검토).

## 구조

`templates/`는 기본값 → 첫 실행 시 `config/`로 복사됩니다.
`config/`가 실제 설정이며 gitignored — 별도 private repo로 관리합니다.

```text
dotfiles/                              # public: 프레임워크
├── bin/dotfiles                       #   CLI: apply / push / status / machines
├── .claude/skills/
│   ├── setup/                         #   /setup (인스톨러)
│   ├── uninstall/                     #   /uninstall (제거/복원)
│   └── sync-setup/                    #   /sync-setup (머신 등록·배포 설정)
├── templates/                         # 기본값 템플릿
│
├── config/                            # private: 내 설정 (gitignored, 별도 repo)
│   ├── machines.toml                  #   배포 대상 머신 (components, transport)
│   ├── ai/
│   │   ├── AGENTS.md                  #   공유 인스트럭션 → 모든 도구
│   │   ├── skills/                    #   공용 자작 스킬 → 모든 도구
│   │   ├── skills-manifest.toml       #   서드파티 스킬 선언 (npx skills)
│   │   ├── claude/
│   │   │   ├── settings.base.json     #   → ~/.claude/settings.json 에 병합
│   │   │   ├── skills/                #   Claude 전용 (서브에이전트 의존)
│   │   │   ├── agents/                #   커스텀 서브에이전트
│   │   │   └── marketplace/           #   플러그인 마켓플레이스
│   │   └── codex/
│   │       ├── config.base.toml       #   → ~/.codex/config.toml 에 병합
│   │       ├── skills/                #   Codex 전용
│   │       └── rules/
│   └── shell/
│       ├── zshrc                      #   guard 기반 공통 설정
│       └── zshrc.d/                   #   macos.zsh / linux.zsh
│
├── backup/                            # 설치 이전 원본 (gitignored)
└── README.md
```

## 여러 머신에서 쓰기 (제어 머신 모델)

```
[제어 머신] config/ 편집 → 심링크로 즉시 로컬 반영 → git commit
    → dotfiles push --all      # 각 머신: git pull → apply → verify
    → dotfiles status          # 머신별 배포 상태·드리프트 확인
```

1. `/sync-setup`으로 private repo(허브)와 머신 등록(`config/machines.toml`)을 설정
2. 각 머신에 1회 부트스트랩 (clone 2개 + `bin/dotfiles apply`)
3. 이후 제어 머신에서 `dotfiles push`

규칙:

- **배포되는 것은 항상 커밋** — 로컬이 dirty면 push가 중단됩니다
- **원격이 dirty면 건너뛰고 보고** — `--force`로만 덮어씁니다
- **secrets는 배포하지 않음** — push 전 secret 스캔이 돌고, 키·토큰은 각 머신의 `~/.zshrc.d/secrets.zsh`(동기화 제외)에 둡니다
- GitHub 접근이 안 되는 머신은 `transport = "direct"`(ssh 직접 push)로 지정

> Syncthing 병행은 지원하지 않습니다 — 실시간 파일 동기화가 원격 tree를 dirty로 만들어 git pull과 충돌합니다.

## config 관리

```bash
cd ~/dotfiles/config
git init && git add -A && git commit -m "initial config"
git remote add origin git@github.com:<username>/dotfiles-config.git
git push -u origin main
```

- **Public repo** (`dotfiles`) — 프레임워크 + 템플릿. 누구나 fork할 수 있습니다.
- **Private repo** (`dotfiles-config`) — 개인 스킬, 에이전트, 권한 설정, 머신 목록.
