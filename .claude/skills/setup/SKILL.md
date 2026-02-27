---
name: setup
description: "dotfiles 초기 설치. 환경 분석, AI 도구 설정, 셸 구성을 자동으로 처리. setup, install, configure 요청 시 트리거."
allowed-tools:
  - Bash(bash *)
  - Read
  - Write
  - Edit
---

# /setup — dotfiles 인스톨러

dotfiles 설치 전 과정을 단계별로 수행한다.
각 단계에서 스크립트 결과를 파싱하고, AI가 판단하여 다음 액션을 결정한다.

## 사전 조건

- 현재 디렉토리가 `~/dotfiles` (또는 dotfiles 레포 루트)인지 확인
- 아니라면 사용자에게 안내하고 중단

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

- **예** → Step 7에서 동기화 방법 안내
- **아니오** → 현재 OS 전용 설정으로 진행

## Step 3: config 초기화

config/ 디렉토리가 없는 경우 (최초 실행):

```bash
bash .claude/skills/setup/scripts/init-config.sh
```

config/가 이미 존재하면 이 단계를 건너뛴다.

### 통합 모드 처리 (Q2에서 "통합" 선택 시)

init-config.sh 실행 후 추가 작업:

1. `config/ai/AGENTS.md`가 실제 파일인지 확인
2. `config/ai/CLAUDE.md`를 `config/ai/AGENTS.md`의 심링크로 변경
3. `config/ai/GEMINI.md`를 `config/ai/AGENTS.md`의 심링크로 변경

```bash
cd ~/dotfiles/config/ai
ln -sf AGENTS.md CLAUDE.md
ln -sf AGENTS.md GEMINI.md
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

선택된 각 AI 도구에 대해:

```bash
bash .claude/skills/setup/scripts/link-tool.sh claude
bash .claude/skills/setup/scripts/link-tool.sh codex
bash .claude/skills/setup/scripts/link-tool.sh gemini
```

각 스크립트의 출력을 확인하여 성공/실패를 파악한다.
기존 설정 파일이 있었다면 `backup/` 폴더에 홈 디렉토리 구조를 미러링하여 백업된다.

## Step 5: 셸 셋업

### 의존성 확인

셸 설정이 의존하는 도구가 미설치면 설치를 제안한다. 강제 설치는 하지 않으며, 건너뛸 수 있다.

#### Oh My Zsh (셸이 zsh인 경우)

```bash
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
```

#### nvm

```bash
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
```

### 심링크 생성

```bash
bash .claude/skills/setup/scripts/link-shell.sh <zsh|bash>
```

각 스크립트의 출력을 확인하여 성공/실패를 파악한다.
기존 설정 파일이 있었다면 `backup/` 폴더에 홈 디렉토리 구조를 미러링하여 백업된다.

## Step 6: 백업 커밋

backup/ 폴더에 파일이 생겼다면 git commit으로 보존한다:

```bash
cd ~/dotfiles
git add backup/
git commit -m "backup: pre-dotfiles original configs"
```

이렇게 하면 원본 설정이 git 히스토리에 남아 안전하게 보존된다.

## Step 7: 검증

```bash
bash .claude/skills/setup/scripts/verify.sh
```

출력을 파싱한다:
- `[ok]` 항목 → 정상
- `[fail]` 항목 → 문제 발견

문제가 발견되면:
1. 원인을 분석한다 (경로 오류, 권한 문제, 소스 파일 부재 등)
2. 자동 복구를 시도한다
3. 복구 후 verify.sh를 다시 실행하여 확인
4. 해결 불가능하면 사용자에게 수동 조치 방법을 안내

## Step 8: 후속 안내

설치 완료 후 다음을 안내한다:

### 셸 적용

```bash
source ~/.zshrc   # 또는 source ~/.bashrc
```

### config/ 개인 Git 관리

```bash
cd ~/dotfiles/config
git init
git add -A && git commit -m "initial config"
git remote add origin <your-private-repo-url>
git push -u origin main
```

### 멀티 머신 동기화 (Q3에서 "예" 선택 시)

동기화 방법을 안내한다:
- **Git**: 각 머신에서 config/ private repo push/pull
- **Syncthing**: 실시간 동기화 (.git은 .stignore에 추가)
- **Git + Syncthing**: Syncthing으로 실시간, Git으로 히스토리

### 커스터마이징 가이드

- `config/` 내 파일을 자유롭게 편집
- `templates/`는 기본값이므로 건드리지 않아도 됨
- 새 스킬 추가: `config/ai/claude/skills/<name>/SKILL.md`
- 변경 후 `/setup`을 다시 실행하면 심링크가 갱신됨
