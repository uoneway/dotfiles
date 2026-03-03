# dotfiles

AI 코딩 도구(Claude Code, Codex CLI, Gemini CLI)와 셸(zsh/bash) 설정을 한 곳에서 관리합니다.

## Why dotfiles

Claude Code, Codex CLI, Gemini CLI — AI 코딩 도구마다 설정 파일 위치가 다릅니다. 글로벌 인스트럭션을 바꾸려면 `~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md`, `~/.gemini/GEMINI.md`를 각각 열어서 같은 내용을 반복 수정해야 합니다. 새 도구가 추가되면 또 하나 늘어납니다.

셸 설정은 더 까다롭습니다. 어떤 함수나 명령어는 공통으로 사용 가능하지만, 어떤 경우에는 OS가 macOS인지 Linux인지 등에 따라 달라져야 할 수도 있습니다. 하나의 `.zshrc`에 전부 우겨넣으면 금세 복잡해지고, 머신마다 미묘하게 다른 설정을 관리하기 어려워집니다.

이 프로젝트는 **모든 설정을 `config/` 한 폴더에 모으고, symlink로 각 도구의 원래 위치에 연결하기에 기존에 설정을 관리하던 방식을 그대로 유지하면서도 중복을 최소화하고 수정사항을 모든 AI 도구에, 모든 머신에 반영할 수 있습니다. .** AI 코딩 도구에서 공통으로 적용할 인스트럭션(`AGENTS.md`)은 하나의 파일로 모두 적용되도록 하되,  도구별로 달라야 하는 설정(`settings.json`, `config.toml` 등)을 분리합니다. 공통 alias와 함수는 `zshrc`에, OS별로 달라지는 부분은 `zshrc.d/macos.zsh`, `zshrc.d/linux.zsh`로 나눠서 관리합니다. `config/`라는 한 폴더 안에 모든 설정이 담겨있기에, Git이나 Syncthing으로 이 폴더만 동기화하면 여러 머신에서 동일한 환경을 유지할 수 있습니다.

## Quick Start

```bash
git clone https://github.com/<username>/dotfiles ~/dotfiles
cd ~/dotfiles
claude
→ /setup
```

## What `/setup` Does

`/setup` skill을 통해 사용자 환경과 선택에 맞는 최적의 환경을 자동으로 구현할 수 있습니다.

**설치한 것을 되돌릴 수 있나요?**
기존 설정 파일은 `dotfiles/backup/` 폴더에 홈 디렉토리 구조 그대로 보존되고, git commit까지 되므로 안전합니다. 실제 파일 대신 심링크만 생성하는 방식이라 원본이 손상되지 않습니다. dotfiles 사용을 그만두고 싶으면 `/uninstall`을 실행하세요. 설치 이전 백업과 사용 중 변경한 현재 설정을 비교해서 어떤 부분을 살릴지 물어본 뒤, 원본 복원 / 현재 설정 유지 / 병합 중 선택할 수 있습니다.

### `/setup` 진행 순서

1. **환경 감지** — OS, 셸, 설치된 AI 도구를 자동으로 판별합니다
2. **선택** — 어떤 도구를 설정할지, 인스트럭션 공유 방식, 멀티 OS 여부를 물어봅니다
3. **config 초기화** — 첫 실행이면 `templates/` → `config/`로 기본값을 복사합니다
4. **AI 도구 셋업**
   - 단계2에서 선택한 AI 도구 설정 (`~/.claude/`, `~/.codex/`, `~/.gemini/`)에 심링크로 연결합니다
   - 만약 선택한 AI 도구가 아직 미설치면 설치 방법을 안내하고 설치를 제안합니다.
5. **셸 셋업**
   - 기존 셸 설정 파일을 분석하여 공통/OS별/프레임워크 의존 항목으로 분류합니다
   - 각 항목이 현재 환경에서 유효한지 검증합니다 (참조 도구 설치 여부, 경로 존재 여부, OS 적합성 등)
   - 문제가 발견되면 처리 방안(설치/제거/OS별 파일로 이동/건너뛰기)을 제시하고 선택받습니다
   - 멀티 OS 사용 시 공통 설정과 OS별 설정을 자동 분리하여 `zshrc` + `zshrc.d/macos.zsh`, `zshrc.d/linux.zsh`로 구성합니다
   - 최종 셸 파일을 홈 디렉토리에 심링크로 연결합니다
6. **검증** — 문제가 있으면 자동으로 수정합니다

### 영향받는 경로

다음 중 사용자에게 해당하는 설정에만 적용됩니다. 기존 파일이 있으면 `backup/` 폴더에 보존한 뒤 심링크를 생성합니다.

**AI 도구:**

- **Claude Code** — `~/.claude/` 내 settings.json, CLAUDE.md, skills/, agents/
- **Codex CLI** — `~/.codex/` 내 config.toml, AGENTS.md, rules/
- **Gemini CLI** — `~/.gemini/` 내 settings.json, GEMINI.md

**셸:**

- **zsh** — `~/.zshrc`, `~/.zshrc.d/`
- **bash** — `~/.bashrc`, `~/.bashrc.d/`

## 구조

`templates/`는 기본값입니다. 첫 실행 시 `config/`로 복사되어 출발점이 됩니다.
`config/`가 실제 설정입니다. 심링크는 여기서만 생성됩니다. Gitignored이므로 개인 설정이 공개 레포에 노출되지 않습니다.

```text
dotfiles/
├── .claude/
│   └── skills/
│       ├── setup/                     #   /setup (인스톨러)
│       └── uninstall/                 #   /uninstall (제거/복원)
│
├── templates/                         # 기본값 템플릿 (→ 설치과정에서 config/로 복사됨)
│
├── config/                            # 내 설정 (gitignored)
│   ├── ai/
│   │   ├── claude/
│   │   │   ├── settings.json          #   → ~/.claude/settings.json
│   │   │   ├── skills/                #   → ~/.claude/skills/
│   │   │   └── agents/                #   → ~/.claude/agents/
│   │   ├── codex/
│   │   │   ├── config.toml            #   → ~/.codex/config.toml
│   │   │   └── rules/                 #   → ~/.codex/rules/
│   │   ├── gemini/
│   │   │   └── settings.json          #   → ~/.gemini/settings.json
│   │   ├── CLAUDE.md                  #   → ~/.claude/CLAUDE.md
│   │   ├── AGENTS.md                  #   → ~/.codex/AGENTS.md
│   │   └── GEMINI.md                  #   → ~/.gemini/GEMINI.md
│   └── shell/
│       ├── zshrc                      #   → ~/.zshrc
│       ├── zshrc.d/                   #   → ~/.zshrc.d/
│       ├── bashrc                     #   → ~/.bashrc
│       └── bashrc.d/                  #   → ~/.bashrc.d/
│
├── backup/                            # 설치 이전 원본 (홈 디렉토리 구조 미러링)
│   ├── .zshrc                         #   ~/.zshrc 원본
│   ├── .claude/                       #   ~/.claude/ 원본
│   ├── .codex/                        #   ~/.codex/ 원본
│   └── ...
│
├── install.sh
└── README.md
```

## config 관리

`config/`는 gitignored이지만, 별도 private repo로 관리할 수 있습니다:

```bash
cd ~/dotfiles/config
git init && git add -A && git commit -m "initial config"
git remote add origin git@github.com:<username>/dotfiles-config.git
git push -u origin main
```

- **Public repo** (`dotfiles`) — 프레임워크 + 템플릿. 누구나 fork할 수 있습니다.
- **Private repo** (`dotfiles-config`) — 개인 스킬, 에이전트, API 권한 설정을 담습니다.

## 여러 머신에서 쓰기

- **Git** — 각 머신에서 `config/` repo를 push/pull 하세요
- **Syncthing** — `~/dotfiles/` 전체를 실시간 동기화합니다 (`.stignore`에 `.git` 추가)
- **둘 다** — Syncthing으로 실시간, Git으로 히스토리를 관리하세요
