# dotfiles

AI 코딩 도구(Claude Code, Codex CLI)와 셸(zsh) 설정을 한 곳에서 관리하고, 여러 머신에 배포합니다.

## Why dotfiles

AI 코딩 도구마다 글로벌 인스트럭션을 찾는 위치가 다릅니다. Claude Code는 홈 디렉토리의 `AGENTS.md`, Codex는 `~/.codex/AGENTS.md`를 사용하므로 별도로 관리하면 같은 내용을 반복해서 수정해야 합니다. 셸 설정은 머신·OS마다 미묘하게 달라지고, 스킬은 도구마다 따로 설치해야 합니다.

이 프로젝트는 **모든 설정을 `config/` 한 폴더에 모으고, 각 도구의 원래 위치에 연결**합니다:

- **인스트럭션 (AGENTS.md)** — 공통 파일을 모든 도구에 공유하고, 지정된 머신에서만 추가 파일을 합침
- **스킬 (SKILL.md)** — 공용 스킬은 한 벌만 두고 per-skill 심링크로 각 도구에 배포. 서드파티 스킬은 manifest 선언 + `npx skills`로 설치
- **설정 (settings.json / config.toml)** — 심링크가 아닌 **병합**: 도구가 런타임에 머신 상태를 쓰는 파일이라, 내가 관리하는 base 키만 교체하고 나머지는 보존
- **셸 (zshrc)** — feature-detection(guard) 기반 공통 설정 + OS 자동 선택 파일 + 지정된 머신의 추가 파일 + 로컬 레이어(local.zsh/secrets.zsh, 동기화 제외)

여러 머신 배포는 두 방식으로 나뉩니다. SSH로 상시 접근할 수 있는 머신은 제어 머신의 `dotfiles push`로 배포합니다. 이동하며 네트워크가 바뀌는 랩탑은 해당 랩탑의 `dotfiles pull`로 갱신합니다.

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

`apply`는 `config/machines.toml`의 `apps` 목록을 설치한 뒤 설정을 적용합니다. 설치 방법은 공용 `apps.json`에 정의하고, 개인 `config/apps.json`으로 앱을 추가하거나 지정한 필드만 덮어씁니다. `[local]`은 이름 없는 로컬 실행 전용 설정이며 설치할 앱은 `local.apps`에서 선택합니다. `[defaults]`는 등록된 머신이 생략한 설정의 공통 기본값으로, `components`, `apps`, 배포 방식과 경로, 추가 인스트럭션·셸 설정을 지원합니다. [앱 설치와 버전 선택](docs/INSTALL_APPS.md)을 참고하세요. 설치를 건너뛰려면 `apply --skip-install`을 사용합니다.

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
| `~/AGENTS.md` (글로벌 인스트럭션) | ✅ | 기본은 `config/ai/AGENTS.md` 심링크. `machines.toml`에 `agents_addition`이 있으면 공통 파일과 추가 파일을 합친 결과에 링크 |
| `settings.json` 중 base 키 — permissions(allow/deny/ask), model, effortLevel, language, theme, statusLine, skillOverrides, env, 알림 설정 | ✅ | **병합** — `settings.base.json`의 키만 교체 |
| 플러그인 (`enabledPlugins`, `extraKnownMarketplaces`, `pluginConfigs`) | ✅ | 선언과 설정이 base로 동기화 → 각 머신이 자동 설치 |
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

Claude Code는 2.1.277 이상이어야 `AGENTS.md`를 직접 읽는다. `~/AGENTS.md`는 홈 디렉토리 아래에서 실행한 세션에 적용된다. Bedrock, Vertex, Foundry나 기능 플래그를 받지 않는 환경에서는 이 기능을 사용할 수 없다.

### Codex CLI (`~/.codex/`)

| 항목 | 동기화 | 방식 / 이유 |
|---|:---:|---|
| `~/.codex/AGENTS.md` (글로벌 인스트럭션) | ✅ | 기본은 `config/ai/AGENTS.md` 심링크. 머신별 추가 파일을 선택하면 Claude와 같은 합성 결과에 링크 |
| `config.toml` 중 base 키 — model, model_verbosity, model_reasoning_effort, approval_policy, sandbox_mode, web_search, personality, commit_attribution, `[tui]`, `[features]`, network_access | ✅ | **병합** — `config.base.toml`의 키만 교체 |
| `rules/` (실행 정책) | ✅ | 심링크 |
| `~/.agents/skills/` (자작 스킬) | ✅ | per-skill 심링크 (공용 `ai/skills/` + Codex 전용). Codex의 user-level 스킬 경로이며, 예전 `~/.codex/skills`에 남은 config 스킬은 apply가 정리 |
| `~/.agents/skills/` (서드파티 스킬) | ✅ | `skills-manifest.toml` 선언 → `npx skills`가 설치·갱신. 자작 스킬 심링크와 같은 디렉토리에 공존 |
| 내장 스킬 끄기 | ✅ | `config/ai/codex/disabled-system-skills`에 적은 이름을 `config.toml`의 `[[skills.config]] enabled = false`로 보장 (경로가 머신마다 달라 base 병합 대신 apply가 추가) |
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
| `zshrc` (guard 기반 공통), `zshrc.d/{macos,linux}.zsh` | ✅ | 심링크. `uname`으로 OS별 파일 자동 선택 |
| `terminal/zsh/additions/`의 선택된 파일 | ✅ | `machines.toml`의 `zsh_addition`을 `~/.zshrc.d/machine-addition.zsh`에 링크해 로드 |
| `zshrc.d/local.zsh` (머신 전용 설정) | ❌ | 의도적 로컬 실파일 |
| `zshrc.d/secrets.zsh` (API 키·토큰) | ❌ | **절대 동기화 금지** — push 전 secret 스캔이 이중 방어 |

### 터미널 앱과 실행 도구

`terminal` 컴포넌트는 셸 설정, 설치된 Ghostty·Herdr의 설정, `config/bin/`의 실행 파일을 적용한다. 기존 `shell` 컴포넌트 이름도 같은 동작을 하는 호환 별칭으로 지원한다. 앱 설치 선택은 여전히 `apps`가 결정한다.

- Ghostty: `terminal/ghostty/common.conf`와 `profiles/*.conf`를 파일별로 링크한다. 기존 기본 설정은 `~/.config/ghostty/local.conf`에 보존하고, 이미 로컬 파일이 있으면 기존 설정을 `local.pre-dotfiles.conf`에 보존한다. 기본 설정은 공통 → 기존 머신 설정 → 로컬 설정 순서로 읽는다. 공통과 동일한 기존 설정 줄은 로컬 파일에 중복하지 않는다. 로컬 파일은 동기화하지 않는다.
- Herdr: `terminal/herdr/config.base.toml`에 정의된 키만 `~/.config/herdr/config.toml`에 병합한다. 그 외 머신별 키, 등록 머신, 세션, 로그, 소켓은 보존한다. 실행 중인 서버는 설정만 다시 로드하고 pane을 재시작하지 않는다. `terminal.shell_mode = "login"`은 새 pane부터 적용된다.
- `config/bin/hdr`: `~/.local/bin/hdr`에 링크한다. Ghostty에서 별도 창을 열 때만 `profiles/herdr.conf`를 적용하므로 일반 창의 키 매핑은 유지된다.

### macOS 키보드 설정

`config/keyboard/macos.json`이 있으면 `dotfiles apply`가 macOS 사용자 환경설정에 적용한다. `dotfiles pull`도 두 저장소를 갱신한 뒤 같은 설정을 적용한다. Linux에서는 건너뛰며 Karabiner 설치 여부와는 무관하다. `verify`는 값을 읽어 확인하고, 설정이 달라도 변경하지 않는다.

지원 키는 `TSMLanguageIndicatorEnabled`(정수 `0` 또는 `1`), `InitialKeyRepeat`(정수 `11`), `KeyRepeat`(정수 `1`)이다. 입력 소스 표시 기능을 끄면 연속 한영 전환 지연을 줄일 수 있으며 다른 형태의 전환 UI는 나타날 수 있다. 키 반복 설정은 길게 누른 키의 반복 시작 대기 시간과 반복 속도를 높인다. 변경은 `dotfiles apply`로 적용하며, 전체 반영에는 로그아웃 후 로그인이 필요할 수 있다. 원복은 원하는 키를 `macos.json`에서 제거한 뒤 `defaults delete -g <키>`를 각 Mac에서 실행한다. 설정 파일에서 키를 제거해도 기존 시스템 값은 자동 삭제하지 않는다.

### Karabiner-Elements (macOS)

`config/keyboard/karabiner.json`은 Karabiner의 원래 JSON 구조를 사용한다. Mac에 Karabiner-Elements가 설치되어 있으면 `dotfiles apply`가 공용 설정(`global`과 프로파일의 기기 외 설정)을 로컬 `~/.config/karabiner/karabiner.json`에 덮어쓴다. 각 프로파일의 `devices`는 `identifiers` 전체가 같으면 그 기기 항목을 통째로 교체하고, 없으면 추가한다. 공용 파일에 없는 로컬 기기는 유지한다. 적용 전 기존 파일은 `backup/.config/karabiner/karabiner.json`에 한 번 백업하며, `verify`는 같은 병합 결과인지 확인한다. Linux 머신과 Karabiner가 설치되지 않은 Mac에서는 건너뛴다.

Ghostty의 `config-file` 상대경로는 그 줄을 적은 설정 파일의 디렉터리를 기준으로 한다. 기본 설정에 `config-file = profiles/herdr.conf`를 넣으면 일반 창에도 Herdr용 키 매핑이 적용되므로, 전용 창만 사용할 때는 `hdr`가 프로파일을 전달하게 둔다.

`apply`와 `verify`는 `local.zsh`에 공통과 같은 이름의 변수·alias·함수 선언이 있거나 Ghostty 로컬 파일에 공통과 같은 옵션이 있으면 경고한다. 경고는 적용을 막지 않으며 값은 출력하지 않는다. 정적으로 인식하는 선언만 검사하므로 동적 `eval`, 추가 `source` 파일, 간접 선언은 감지하지 못할 수 있다. `secrets.zsh`는 검사하지 않는다.

Bash 설정은 배포하지 않는다. 서버의 기존 `~/.bashrc`는 머신 로컬로 유지하고, 로그인 셸을 바꿀 수 없는 환경에서는 인터랙티브 셸에서만 zsh로 전환하는 블록을 추가한다. 프레임워크 스크립트를 실행하는 Bash는 계속 필요하다. zsh가 없는 머신은 셸 설정을 적용하기 전에 zsh를 설치해야 한다.

`aladd 이름 "명령"`과 `aladd --local 이름 "명령"`은 `~/.zshrc.d/local.zsh`에 alias를 저장한다. `aladd --shared 이름 "명령"`은 심링크로 연결된 `config/terminal/zsh/zshrc`의 공통 alias 영역에 저장한다. 공통 함수와 alias는 zshrc에서 함께 관리하고, zshrc.d에는 OS별 macos.zsh·linux.zsh를 둔다. 공통 alias는 머신별·로컬 설정보다 먼저 읽으며, 다른 머신에 적용하려면 config 저장소를 커밋하고 배포해야 한다. 두 방식 모두 명령을 셸 문법에 맞게 인용해 저장하고 현재 셸에도 적용한다. 로컬 대상이 심링크이면 기록을 거부하며, 공통 대상은 관리되는 심링크인지 확인한다. `al-edit`는 로컬 파일을 편집한다.

Gemini CLI는 템플릿만 제공하며 기본 비활성입니다 (Antigravity 전환이 안정되면 재검토).

## 구조

`templates/`는 기본값 → 첫 실행 시 `config/`로 복사됩니다.
`config/`가 실제 설정이며 gitignored — 별도 private repo로 관리합니다.

```text
dotfiles/                              # public: 프레임워크
├── bin/dotfiles                       #   CLI: apply / pull / push / status / machines
├── apps.json                          #   공용 앱 설치 방법과 기본 버전
├── .claude/skills/
│   ├── setup/                         #   /setup (인스톨러)
│   ├── uninstall/                     #   /uninstall (제거/복원)
│   └── sync-setup/                    #   /sync-setup (머신 등록·배포 설정)
├── templates/                         # 기본값 템플릿
│
├── config/                            # private: 내 설정 (gitignored, 별도 repo)
│   ├── machines.toml                  #   배포 대상 머신과 apps 설치 목록
│   ├── apps.json                      #   개인 앱 추가와 필드 덮어쓰기
│   ├── installers/                    #   개인 설치 스크립트
│   ├── ai/
│   │   ├── AGENTS.md                  #   공유 인스트럭션 → 모든 도구
│   │   ├── agents-additions/          #   machines.toml에서 선택하는 추가 인스트럭션
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
│   ├── terminal/                     #   터미널 작업 환경
│   │   ├── zsh/                      #   zshrc, zshrc.d/, additions/
│   │   ├── ghostty/                  #   common.conf, profiles/herdr.conf
│   │   └── herdr/config.base.toml    #   공통 키만 라이브 config.toml에 병합
│   ├── keyboard/karabiner.json        #   macOS Karabiner 공용·기기별 설정
│   └── bin/hdr                       #   → ~/.local/bin/hdr
│
├── backup/                            # 설치 이전 원본 (gitignored)
└── README.md
```

## 여러 머신에서 쓰기

### SSH로 접근 가능한 머신에 배포하기

```
[제어 머신] config/ 편집 → 심링크로 즉시 로컬 반영 → git commit
    → dotfiles push --all      # 각 머신: git pull → apply → verify
    → dotfiles status          # 머신별 배포 상태·드리프트 확인
```

1. `/sync-setup`으로 private repo(허브)와 머신 등록(`config/machines.toml`)을 설정
2. 각 머신에 1회 부트스트랩 (clone 2개 + `bin/dotfiles apply`)
3. 이후 제어 머신에서 `dotfiles push`

`config/machines.toml`의 `agents_addition`과 `zsh_addition`으로 머신별 추가 파일을 선택한다. 파일은 각각 `config/ai/agents-additions/`와 `config/terminal/zsh/additions/`에 둔다.

`push`는 머신 이름을 원격 `apply`에 전달한다. 원격에서 직접 `dotfiles apply`를 실행해도 저장된 이름으로 같은 파일을 선택한다. 제어 머신과 이동형 랩탑은 목록에 없으므로 공통 설정만 적용한다. 셸의 macOS/Linux 선택은 모든 머신에서 자동으로 이뤄진다.

규칙:

- **배포되는 것은 항상 커밋** — 로컬이 dirty면 push가 중단됩니다
- **원격이 dirty면 건너뛰고 보고** — `--force`로만 덮어씁니다
- **secrets는 배포하지 않음** — push 전 secret 스캔이 돌고, 키·토큰은 각 머신의 `~/.zshrc.d/secrets.zsh`(동기화 제외)에 둡니다
- GitHub 접근이 안 되는 머신은 `transport = "direct"`(ssh 직접 push)로 지정

### 이동형 랩탑에서 동기화하기

네트워크가 자주 바뀌거나 절전하는 랩탑은 `config/machines.toml`에 등록하지 않습니다. 랩탑에서 다음 명령을 실행하면 두 저장소를 `fast-forward`로 갱신한 뒤 설정을 적용하고 검증합니다.

```bash
dotfiles pull
```

랩탑에는 두 저장소를 한 번씩 clone하고 GitHub 접근 권한을 설정해야 합니다. 로컬 변경이 있거나 원격 이력과 갈라졌으면 `dotfiles pull`은 덮어쓰지 않고 중단합니다. 이 방식은 랩탑으로 들어오는 SSH 연결이 필요하지 않습니다.

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
