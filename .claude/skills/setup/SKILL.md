---
name: setup
description: "dotfiles 초기 설치. 환경 분석, AI 도구 설정, 셸 구성을 자동으로 처리. setup, install, configure 요청 시 트리거."
model: sonnet
allowed-tools:
  - Bash(bash .claude/skills/setup/scripts/*)
  - Bash(ln -sf *)
  - Bash(curl *)
  - Bash(sh -c *)
  - Bash(npm install -g *)
  - Bash(cd *)
  - AskUserQuestion
  - Read
  - Write
  - Edit
  - Glob
---

# /setup — dotfiles 인스톨러

dotfiles 설치 전 과정을 단계별로 수행한다.
각 단계에서 스크립트 결과를 파싱하고, AI가 판단하여 다음 액션을 결정한다.

## Step 0: 환영 메시지

사용자에게 다음을 출력한다:

```
dotfiles setup을 시작합니다.

AI 도구(Claude Code, Codex CLI, Gemini CLI)와 셸 설정을
config/ 한 곳에서 관리하고, symlink로 각 도구에 연결합니다.

환경을 분석하고 몇 가지 질문을 드린 뒤 자동으로 설정합니다.
```

그 후 현재 디렉토리가 dotfiles 레포 루트인지 확인한다.
아니라면 사용자에게 안내하고 중단한다.

## Step 1: 환경 분석

```bash
bash .claude/skills/setup/scripts/check-env.sh
```

출력을 파싱하여 다음을 파악한다:
- OS (macOS / Linux)
- 현재 셸 (zsh / bash)
- 설치된 AI 도구 (claude, codex, gemini)
- Oh My Zsh 설치 여부
- nvm 설치 여부
- config/ 존재 여부 (최초 실행인지)

결과를 사용자에게 요약해서 보여준다.

## Step 2: 사용자 질문

AskUserQuestion으로 3가지를 질문한다.

### Q1. AI 도구 선택

"어떤 AI 도구를 설정할까요?"

- 옵션: Claude Code, Codex CLI, Gemini CLI (복수 선택 가능)
- 미설치 도구도 선택 가능 — Step 4에서 설치 안내
- 기본값: 감지된 도구 모두

### Q2. 글로벌 인스트럭션 공유 전략

"AI 도구 간 글로벌 인스트럭션을 어떻게 관리할까요?"

- **통합**: 하나의 `AGENTS.md`를 작성하고 `CLAUDE.md`, `GEMINI.md`를 이것의 심링크로 연결
  - 장점: 한 파일만 편집하면 모든 도구에 적용
  - 적합: 도구 간 일관된 지시를 원할 때
- **개별**: 각 도구마다 독립 인스트럭션 파일 유지
  - 장점: 도구별 최적화 가능
  - 적합: 도구마다 다른 지시를 내리고 싶을 때

### Q3. 멀티 OS 사용 여부

"여러 OS(macOS/Linux)에서 이 dotfiles를 사용하시나요?"

- **예** → 추가 질문: "현재 OS는 {Step 1에서 감지된 OS}입니다. 추가로 사용하는 OS를 선택해주세요." (macOS / Linux 중 현재 OS가 아닌 것)
  - Step 5에서 셸 설정을 공통/OS별로 분리하고, Step 7에서 동기화 방법 안내
- **아니오** → 현재 OS 전용 설정으로 진행 (Step 5에서 현재 OS에 맞지 않는 설정만 정리)

## Step 3: config 초기화

config/ 디렉토리가 없는 경우 (최초 실행):

```bash
bash .claude/skills/setup/scripts/init-config.sh
```

config/가 이미 존재하면 이 단계를 건너뛴다.

### 인스트럭션 모드 처리 (Q2 결과에 따라)

init-config.sh 실행 후 Q2 선택에 따라 추가 작업:

**통합 모드**: `config/ai/AGENTS.md` 하나만 사용. 각 도구별 인스트럭션 파일이 있으면 삭제한다.

```bash
rm -f ~/dotfiles/config/ai/claude/CLAUDE.md
rm -f ~/dotfiles/config/ai/codex/AGENTS.md
rm -f ~/dotfiles/config/ai/gemini/GEMINI.md
```

**개별 모드**: 각 도구 폴더에 개별 인스트럭션 파일을 생성한다. `config/ai/AGENTS.md`의 내용을 초기값으로 복사한다.

```bash
cp ~/dotfiles/config/ai/AGENTS.md ~/dotfiles/config/ai/claude/CLAUDE.md
cp ~/dotfiles/config/ai/AGENTS.md ~/dotfiles/config/ai/codex/AGENTS.md
cp ~/dotfiles/config/ai/AGENTS.md ~/dotfiles/config/ai/gemini/GEMINI.md
```

## Step 4: AI 도구 셋업

Step 1 결과를 기반으로 AI가 판단한다.

### 미설치 AI 도구 안내

Q1에서 선택했지만 미설치인 도구가 있으면 설치 방법을 안내한다:

- **Claude Code**: `curl -fsSL https://claude.ai/install.sh | bash` (macOS/Linux) 또는 `brew install --cask claude-code`
- **Codex CLI**: `npm install -g @openai/codex` 또는 `brew install --cask codex` (macOS)
- **Gemini CLI**: `npm install -g @google/gemini-cli` 또는 `brew install gemini-cli`

사용자가 지금 설치할지, 나중에 할지 선택하게 한다.

### 심링크 생성

선택된 각 AI 도구에 대해 Q2 선택에 따라 `--unified` 또는 `--separate` 플래그를 전달:

```bash
# 통합 모드
bash .claude/skills/setup/scripts/link-tool.sh claude --unified
bash .claude/skills/setup/scripts/link-tool.sh codex --unified
bash .claude/skills/setup/scripts/link-tool.sh gemini --unified

# 개별 모드
bash .claude/skills/setup/scripts/link-tool.sh claude --separate
bash .claude/skills/setup/scripts/link-tool.sh codex --separate
bash .claude/skills/setup/scripts/link-tool.sh gemini --separate
```

각 스크립트의 출력을 확인하여 성공/실패를 파악한다.
기존 설정 파일이 있었다면 `backup/` 폴더에 홈 디렉토리 구조를 미러링하여 백업된다.

## Step 5: 셸 셋업

### 5-1. 기존 셸 설정 분석

사용자의 현재 셸 설정 파일(`~/.zshrc` 또는 `~/.bashrc`)을 읽고, 내용을 항목별로 분석한다.
이미 `config/shell/` 에 셸 파일이 존재하면 그것을 분석 대상으로 한다.

분석 기준:

| 분류 | 판단 기준 | 예시 |
|------|----------|------|
| **공통** | OS에 무관하게 동작하는 설정 | alias, 환경변수(`PATH`에 OS 특정 경로 없는 것), 순수 셸 함수, 프롬프트 설정 |
| **OS별** | OS에 따라 경로·명령어·패키지 관리자가 다른 설정 | Homebrew(`/opt/homebrew/`), `gls` vs `ls`, conda 경로(`miniforge3` vs `miniconda3`), pnpm 경로(`~/Library/`) |
| **프레임워크 의존** | Oh My Zsh, nvm 등 특정 도구가 설치되어 있어야 동작하는 설정 | `source $ZSH/oh-my-zsh.sh`, `plugins=(...)`, `NVM_DIR` |

### 5-2. 환경 유효성 검증

분석한 각 항목이 현재 환경에서 실제로 유효한지 검증한다.

검증 항목:

- **참조 도구 존재 여부**: 설정에 등장하는 명령어/도구가 실제 설치되어 있는지 (`command -v`로 확인)
  - 예: `gls` alias가 있지만 coreutils 미설치, `conda` 설정이 있지만 conda 미설치
- **경로 유효성**: 설정에 하드코딩된 경로가 실제 존재하는지
  - 예: `/opt/homebrew/opt/mysql-client@8.0/bin` 경로가 없는 경우
- **프레임워크 의존성**: Oh My Zsh, nvm, p10k 등이 필요하지만 미설치인 경우
- **OS 적합성**: 현재 OS에서 동작하지 않는 설정이 공통 영역에 포함된 경우

검증 결과를 사용자에게 테이블 형태로 보여준다:

```
셸 설정 검증 결과:

[ok]    alias gs='git status'          — git 설치 확인됨
[ok]    Oh My Zsh 플러그인 (git, z)     — Oh My Zsh 설치 확인됨
[warn]  conda activate (miniforge3)    — miniforge3 미설치 (현재 OS: Linux)
[warn]  gls 사용 (lslh_pretty)          — coreutils 미설치
[fail]  Oh My Zsh                      — 미설치 (셸 설정 전체가 의존)
```

### 5-3. 문제 항목 처리

검증에서 `[warn]` 또는 `[fail]`이 나온 항목에 대해 각각 처리 방안을 제시하고 사용자에게 선택받는다.

#### 핵심 의존성 미설치 (`[fail]` 수준)

셸 설정 전체가 의존하는 핵심 도구(예: 셸 프레임워크, 버전 매니저 등). 미설치 시 설정 파일이 정상 동작하지 않는다.

AskUserQuestion으로 각각 설치 여부를 묻는다. 설치 명령을 제시하되 강제 설치는 하지 않으며, 건너뛸 수 있다.

#### 개별 항목 문제 (`[warn]` 수준)

AskUserQuestion으로 처리 방법을 묻는다. 항목별 선택지:

- **설치**: 해당 도구를 지금 설치 (설치 명령 제시)
- **제거**: 해당 설정을 셸 파일에서 제거
- **OS별 파일로 이동**: 특정 OS에서만 유효한 설정이면 해당 OS 파일로 이동
- **건너뛰기**: 지금은 무시하고 그대로 둠

### 5-4. 셸 파일 생성

분석 결과와 Q3 응답을 종합하여 셸 파일을 구성한다.

#### 멀티 OS인 경우

```
config/shell/
├── zshrc              ← 공통 설정만 (OS 분기 source 포함)
└── zshrc.d/
    ├── macos.zsh      ← macOS 전용 (Homebrew, gls, miniforge3 등)
    └── linux.zsh      ← Linux 전용 (apt 계열, GNU ls, miniconda3 등)
```

- `zshrc` 안에 `uname` 분기로 OS별 파일을 source하는 코드를 포함한다
- 5-1에서 "OS별"로 분류된 항목을 각 OS 파일에 배치한다
- 사용자가 직접 사용하지 않는 OS의 파일은 현재 OS 파일을 참고한 스켈레톤으로 생성하되, 사용자에게 "해당 OS 머신에서 경로 등을 확인 후 수정이 필요합니다"라고 안내한다

#### 단일 OS인 경우

```
config/shell/
├── zshrc              ← 현재 OS 기준 전체 설정
└── zshrc.d/           ← (비어있거나 생략)
```

- 모든 설정을 `zshrc` 하나에 유지한다
- 5-3에서 "제거"를 선택한 항목은 제외한다

### 5-5. 심링크 생성

```bash
bash .claude/skills/setup/scripts/link-shell.sh <zsh|bash>
```

각 스크립트의 출력을 확인하여 성공/실패를 파악한다.
기존 설정 파일이 있었다면 `backup/` 폴더에 홈 디렉토리 구조를 미러링하여 백업된다.

## Step 6: 검증

Q1에서 선택한 도구와 Q2 모드를 전달한다. `--tools`를 생략하면 심링크가 걸린 도구만 자동 감지한다.

```bash
bash .claude/skills/setup/scripts/verify.sh --unified --tools claude,codex
# 또는
bash .claude/skills/setup/scripts/verify.sh --separate --tools claude,codex,gemini
```

출력을 파싱한다:
- `[ok]` 항목 → 정상
- `[fail]` 항목 → 문제 발견

문제가 발견되면:
1. 원인을 분석한다 (경로 오류, 권한 문제, 소스 파일 부재 등)
2. 자동 복구를 시도한다
3. 복구 후 verify.sh를 다시 실행하여 확인
4. 해결 불가능하면 사용자에게 수동 조치 방법을 안내

## Step 7: 완료 및 후속 안내

검증을 통과하면 다음을 출력한다:

```
Setup 완료! dotfiles가 성공적으로 설정되었습니다.

설정된 항목:
```

그 아래에 실제로 설정된 도구와 셸을 요약해서 보여준다. 예:

```
  - Claude Code: ~/.claude/ -> config/ai/claude/
  - Codex CLI:   ~/.codex/  -> config/ai/codex/
  - zsh:         ~/.zshrc   -> config/shell/zshrc

이제 config/ 안의 파일을 편집하면 모든 도구에 반영됩니다.
```

그 후 다음을 안내한다:

### 셸 적용

```bash
source ~/.zshrc   # 또는 source ~/.bashrc
```

### 동기화 설정 제안

config/를 여러 머신에서 동기화하면 어디서든 같은 환경을 유지할 수 있다는 점을 간단히 설명하고, 설정할지 AskUserQuestion으로 묻는다.

- **예** → Skill 도구로 `sync-setup` 스킬을 직접 호출하여 이어서 진행한다.
- **아니오** → 건너뛴다. "나중에 `/sync-setup`으로 언제든 설정할 수 있습니다."

### 커스터마이징 가이드

- `config/` 내 파일을 자유롭게 편집
- `templates/`는 기본값이므로 건드리지 않아도 됨
- 새 스킬 추가: `config/ai/claude/skills/<name>/SKILL.md`
- 변경 후 `/setup`을 다시 실행하면 심링크가 갱신됨
