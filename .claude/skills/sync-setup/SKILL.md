---
name: sync-setup
description: "dotfiles config/ 동기화 설정. Git private repo 또는 Syncthing 설정을 안내. sync, 동기화, git config, syncthing 요청 시 트리거."
model: sonnet
disable-model-invocation: true
allowed-tools:
  - Bash(bash .claude/skills/sync-setup/scripts/*)
  - Bash(brew install syncthing)
  - Bash(brew services *)
  - Bash(syncthing serve *)
  - Bash(pkill *)
  # Git
  - Bash(cd */config && git *)
  - Bash(gh repo create *)
  - Bash(gh api *)
  # Linux
  - Bash(systemctl * syncthing*)
  - AskUserQuestion
  - Read
  - Write
---

# /sync-setup — config/ 동기화 설정

dotfiles `config/`를 여러 머신에서 동기화하기 위한 설정.

**동기화 대상은 `~/dotfiles/config/`만.** 프레임워크는 `git clone`으로, 개인 설정만 동기화.

## Step 1: 동기화 방법 선택

AskUserQuestion:

- **Git (private repo)**: push/pull로 동기화. 히스토리 보존.
- **Syncthing**: 실시간 자동 동기화. 히스토리 없음.
- **둘 다**: Syncthing 실시간 + Git 히스토리.

## Step 2A: Git private repo 설정

사용자가 Git 또는 둘 다 선택 시.

### 1. 상태 확인

```bash
bash .claude/skills/sync-setup/scripts/check-git-config.sh
```

출력을 파싱하여 `has_git`, `has_remote`, `branch` 등을 파악한다.

### 2. git init (has_git=false인 경우)

```bash
cd ~/dotfiles/config && git init && git add -A && git commit -m "initial config"
```

### 3. GitHub private repo 생성 (has_remote=false인 경우)

AskUserQuestion으로 repo 이름을 묻는다 (기본값: `dotfiles-config`).

```bash
gh repo create <username>/<repo-name> --private --description "Personal dotfiles config"
cd ~/dotfiles/config
git remote add origin git@github.com:<username>/<repo-name>.git
git push -u origin main
```

`<username>`은 `gh api user -q .login`으로 감지.

### 4. 이미 remote가 있으면

push할지 AskUserQuestion으로 묻는다.

## Step 2B: Syncthing 설정

사용자가 Syncthing 또는 둘 다 선택 시.

### 1. 상태 확인

```bash
bash .claude/skills/sync-setup/scripts/check-syncthing.sh
```

출력을 파싱하여 다음을 파악한다:
- `installed`: 설치 여부
- `running` / `run_method`: 실행 중인지, 어떤 방식(app/brew/manual)인지
- `autostart`: 자동 시작 등록 방식
- `folder=*`: 등록된 폴더 (id|path 형식)
- `device_id`: 이 기기의 Device ID

### 2. 설치 (installed=false인 경우)

macOS: `brew install syncthing` / Linux: 패키지 매니저 안내.

### 3. 자동 시작 처리

check-syncthing.sh 결과에 따라 분기:

- **autostart=brew_services + running=true** → 정상. 건너뛰기.
- **autostart=brew_services + running=false** → `brew services start syncthing`
- **autostart=brew_services + autostart_status=error** → lock 충돌 가능. `pkill -x syncthing` 후 `brew services restart syncthing`
- **autostart=app_or_manual** → macOS 앱이 자체 관리 중. AskUserQuestion: "macOS 앱 유지" vs "brew services로 전환". 앱 유지 시 brew services 등록 해제 (`brew services stop syncthing`).
- **autostart=none + running=false** → AskUserQuestion: 자동 시작 등록할지.
  - 예 → macOS: `brew services start syncthing` / Linux: `systemctl --user enable --now syncthing.service`
  - 아니오 → `syncthing serve --no-browser &`

### 4. 폴더 등록

check-syncthing.sh의 `folder=` 출력을 파싱하여:

- `dotfiles-config|*/config` 있음 → 건너뛰기
- `dotfiles|*/dotfiles` 있음 → AskUserQuestion: "~/dotfiles 전체가 등록됨. config/만으로 변경할까요?"
  - 예 → `bash .claude/skills/sync-setup/scripts/setup-syncthing-folder.sh --remove-dotfiles`
  - 아니오 → 유지
- 없음 → 아래 실행

```bash
# Git 병용 시
bash .claude/skills/sync-setup/scripts/setup-syncthing-folder.sh --with-git
# Syncthing만
bash .claude/skills/sync-setup/scripts/setup-syncthing-folder.sh
```

### 5. Device ID 및 연결 안내

check-syncthing.sh에서 `device_id=`를 파싱하여 보여준다.

```
다른 기기에서 연결하기:
1. 다른 기기에 Syncthing 설치
2. http://localhost:8384 접속
3. "Add Remote Device" → Device ID 입력
4. 이 기기에서 연결 요청 승인
5. dotfiles-config 폴더를 공유 대상으로 추가
```

## Step 3: 완료 안내

설정 결과를 요약하고 안내:

```
다른 머신에서 사용하기:

1. git clone <dotfiles-repo> ~/dotfiles
2. cd ~/dotfiles/config && git clone <config-repo> .
   (또는 Syncthing으로 자동 동기화 대기)
3. cd ~/dotfiles && claude → /setup
```
