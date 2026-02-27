---
name: sync-setup
description: "dotfiles config/ 동기화 설정. Git private repo 또는 Syncthing 설정을 안내. sync, 동기화, git config, syncthing 요청 시 트리거."
model: sonnet
disable-model-invocation: true
allowed-tools:
  # Git
  - Bash(cd */config && git *)
  - Bash(git *)
  - Bash(gh repo create *)
  - Bash(gh api *)
  # Syncthing
  - Bash(brew install syncthing)
  - Bash(brew services *)
  - Bash(command -v syncthing)
  - Bash(pgrep *)
  - Bash(syncthing cli *)
  - Bash(syncthing serve *)
  # Linux
  - Bash(systemctl * syncthing*)
  # Fallback
  - Bash(curl *)
  # 파일 생성
  - Bash(cat > *)
  - AskUserQuestion
  - Read
  - Write
---

# /sync-setup — config/ 동기화 설정

dotfiles 설치 후 `config/`를 여러 머신에서 동기화하기 위한 설정을 안내한다.

**동기화 대상은 `~/dotfiles/config/`만.** dotfiles 프레임워크(templates/, scripts/)는 `git clone`으로 받으면 되고, 개인 설정인 `config/`만 머신 간 동기화한다.

## Step 1: 동기화 방법 선택

AskUserQuestion으로 질문:

"config/ 동기화 방법을 선택하세요."

- **Git (private repo)**: config/를 별도 private repo로 관리. 변경사항을 커밋하고 push/pull로 동기화. 히스토리가 남아 변경 추적 가능.
- **Syncthing**: 실시간 자동 동기화. 설치 후 폴더만 지정하면 별도 조작 없이 동기화됨. 단, 변경 히스토리 없음.
- **둘 다**: Syncthing으로 실시간 동기화 + Git으로 히스토리 관리. 가장 안전하지만 설정이 두 번.

## Step 2A: Git private repo 설정

사용자가 Git 또는 둘 다를 선택한 경우:

### 1. 현재 상태 확인

```bash
cd ~/dotfiles/config && git remote -v 2>/dev/null
```

### 2. git init (필요한 경우)

.git이 없으면:

```bash
cd ~/dotfiles/config
git init
git add -A && git commit -m "initial config"
```

### 3. GitHub private repo 생성

remote가 없으면 GitHub에 private repo를 만들지 AskUserQuestion으로 묻는다.

원한다면 repo 이름도 묻는다:

- 기본값: `dotfiles-config`
- AskUserQuestion: "Private repo 이름을 정해주세요." (options: "dotfiles-config (Recommended)", "dotfiles-private", "my-config")

사용자가 선택하거나 직접 입력한 이름으로 생성:

```bash
gh repo create <username>/<repo-name> --private --description "Personal dotfiles config"
cd ~/dotfiles/config
git remote add origin git@github.com:<username>/<repo-name>.git
git push -u origin main
```

`<username>`은 `gh api user -q .login`으로 자동 감지한다.

### 4. 이미 remote가 있는 경우

현재 상태를 push할지 묻는다.

## Step 2B: Syncthing 설정

사용자가 Syncthing 또는 둘 다를 선택한 경우.

사용자가 직접 해야 하는 것(다른 기기에서 Device ID 교환)을 제외하고, CLI로 할 수 있는 것은 최대한 자동으로 처리한다.

### 1. 설치

```bash
command -v syncthing
```

미설치 시 (macOS):

```bash
brew install syncthing
```

### 2. 자동 시작 등록 및 Syncthing 시작

자동 시작과 프로세스 시작을 한 번에 처리한다. 순서가 중요하다:

**먼저 현재 상태를 확인한다:**

```bash
# macOS: brew services로 등록 여부 확인
brew services list 2>/dev/null | grep syncthing
# Linux: systemd로 등록 여부 확인
systemctl --user is-enabled syncthing.service 2>/dev/null
# 프로세스 실행 여부
pgrep -x syncthing > /dev/null 2>&1 && echo "RUNNING" || echo "NOT_RUNNING"
```

**분기 처리:**

- **brew services에 이미 등록 + 실행 중** → 건너뛰기
- **brew services에 이미 등록 + 실행 안 됨** → `brew services start syncthing`
- **미등록 + 실행 중** → 다른 방법(cask 앱 등)으로 실행 중. 자동 시작 등록할지 AskUserQuestion으로 묻기. "예"이면 기존 프로세스를 종료하고 `brew services start syncthing`으로 전환
- **미등록 + 실행 안 됨** → 자동 시작 등록할지 AskUserQuestion으로 묻기.
  - "예" → `brew services start syncthing` (등록과 동시에 시작됨)
  - "아니오" → `syncthing serve --no-browser &`로 지금만 시작

**Linux의 경우:**

```bash
# 등록
systemctl --user enable syncthing.service
# 시작
systemctl --user start syncthing.service
```

### 3. ~/dotfiles/config/ 폴더 공유 추가

**`syncthing cli`를 사용한다** (REST API의 CSRF 문제 회피).

```bash
# 현재 설정된 폴더 목록 확인
syncthing cli config folders list
```

**이미 등록된 폴더 확인:**

- `dotfiles-config` (정확히 config/ 대상) → 건너뛰기
- `dotfiles` (~/dotfiles 전체 대상) → 경고: "현재 ~/dotfiles 전체가 동기화 중입니다. config/만 동기화하도록 변경할까요?" AskUserQuestion으로 묻기
- 없음 → 아래 명령으로 추가

```bash
# dotfiles-config 폴더 추가
syncthing cli config folders add --id dotfiles-config --label dotfiles-config --path ~/dotfiles/config
```

### 4. .stignore 생성

`~/dotfiles/config/.stignore`에 생성한다.

**Git과 함께 쓰는 경우 (Step 2A도 선택한 경우):**

```bash
cat > ~/dotfiles/config/.stignore << 'EOF'
.git
EOF
```

**Syncthing만 쓰는 경우:**

.stignore 생성 불필요 (config/ 내에 .git이 없으므로).

### 5. config/.gitignore에 .stfolder 추가

Syncthing은 동기화 추적용으로 `.stfolder` 디렉토리를 자동 생성한다. config/를 Git으로 관리하는 경우(Step 2A 포함) 이를 `.gitignore`에 추가한다. Git 없이 Syncthing만 쓰는 경우에도, 나중에 Git을 추가할 가능성을 고려하여 기본으로 추가한다.

```bash
# .gitignore가 없으면 생성, 있으면 .stfolder가 포함되었는지 확인 후 추가
grep -qxF '.stfolder' ~/dotfiles/config/.gitignore 2>/dev/null || echo '.stfolder' >> ~/dotfiles/config/.gitignore
```

### 6. Device ID 확인 및 다른 기기 연결 안내

```bash
syncthing cli show system | grep myID
```

위 명령이 실패하면 (Syncthing이 아직 초기화 중일 수 있음), 대기 후 재시도하거나 REST API 응답 헤더에서 추출:

```bash
# fallback: 응답 헤더의 X-Syncthing-Id에서 추출
curl -s -o /dev/null -D - http://localhost:8384 | grep X-Syncthing-Id | awk '{print $2}'
```

Device ID를 보여주고 안내한다:

```
다른 기기에서 연결하기:
1. 다른 기기에 Syncthing 설치
2. http://localhost:8384 접속
3. "Add Remote Device" → 위 Device ID 입력
4. 이 기기에서 연결 요청 승인
5. dotfiles-config 폴더를 공유 대상으로 추가
```

## Step 3: 완료 안내

설정 결과를 요약하고, 다른 머신에서 dotfiles를 사용하는 방법을 안내한다:

```
다른 머신에서 사용하기:

1. git clone <dotfiles-repo> ~/dotfiles
2. cd ~/dotfiles/config && git clone <config-repo> .
   (또는 Syncthing으로 자동 동기화 대기)
3. cd ~/dotfiles && claude → /setup
```
