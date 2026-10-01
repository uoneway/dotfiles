---
name: sync-setup
description: "멀티 머신 배포 설정. 머신 등록(machines.toml), 원격 부트스트랩, 기존 Syncthing 정리를 안내. sync, 동기화, 머신 등록, push 설정 요청 시 트리거."
model: sonnet
disable-model-invocation: true
allowed-tools:
  - Bash(bash .claude/skills/sync-setup/scripts/*)
  - Bash(bin/dotfiles *)
  - Bash(grep * ~/.ssh/config)
  - Bash(ssh *)
  # Git
  - Bash(cd */config && git *)
  - Bash(gh repo create *)
  - Bash(gh api *)
  - Bash(brew services *)
  - Bash(syncthing *)
  - AskUserQuestion
  - Read
  - Write
  - Edit
---

# /sync-setup — 멀티 머신 배포 설정

동기화 모델: **제어 머신에서 편집·커밋 → `dotfiles push` → 각 머신이 git pull + apply.**
전송은 git(허브 = private repo), 오케스트레이션은 `bin/dotfiles` CLI가 담당한다.

## Step 1: 허브(private repo) 확인

```bash
bash .claude/skills/sync-setup/scripts/check-git-config.sh
```

- `has_git=false` → `cd ~/dotfiles/config && git init && git add -A && git commit -m "initial config"`
- `has_remote=false` → AskUserQuestion으로 repo 이름(기본 `dotfiles-config`) 확인 후:

```bash
gh repo create <username>/<repo-name> --private --description "Personal dotfiles config"
cd ~/dotfiles/config
git remote add origin git@github.com:<username>/<repo-name>.git
git push -u origin main
```

- 프레임워크(`~/dotfiles`)도 remote가 있는지 확인한다 (원격 머신이 clone해야 하므로).

## Step 2: 머신 등록 (machines.toml)

1. `~/.ssh/config`의 `Host` 항목을 나열해 보여준다 (`grep '^Host ' ~/.ssh/config`).
2. AskUserQuestion으로 등록할 머신을 고르게 한다 (복수 선택).
3. 머신마다 components를 묻는다:
   - 개인 머신 → `shell,claude,codex`
   - 공용 계정 서버 → `shell` 또는 `shell,codex` (개인 권한 설정·스킬 노출 주의)
   - GitHub 접근 불가 머신(폐쇄망 등) → `transport = "direct"` 지정
4. 머신마다 설치할 앱을 선택한다. 설치 방법은 공용 `apps.json`과 개인 `config/apps.json`을 병합한 카탈로그에서 읽는다. `components`는 설정 적용 범위이므로 앱 선택에 사용하지 않는다.
5. `config/machines.toml`에 `apps = ["codex", "claude"]`처럼 목록을 적는다. `apps = []`는 그 머신의 앱 자동 설치를 끈다. 생략하면 `[defaults].apps`를 상속한다. `[defaults]`에는 `components`, `transport`, `path`, `agents_addition`, `zsh_addition`도 지정할 수 있다. 머신에서 생략한 필드만 상속하고 명시한 값은 교체한다. 이름 없는 로컬 실행 전용인 `[local]`은 기본값을 상속하지 않고 등록 머신에도 상속되지 않는다.

[앱 설치 가이드](../../../docs/INSTALL_APPS.md)의 머신별 예시를 참고한다. 원격 부트스트랩 전에 `dotfiles install --machine <이름> --dry-run`으로 정책을 확인한다. 이 명령은 현재 머신에서 정책을 검사하며 SSH로 설치하지 않는다.

## Step 3: 원격 머신 부트스트랩 (머신당 1회)

새 머신에서 (또는 ssh로):

```bash
git clone <framework-repo> ~/dotfiles
git clone <config-repo> ~/dotfiles/config
bash ~/dotfiles/bin/dotfiles apply <components> --machine <machines.toml의-이름>
```

- `transport = "direct"` 머신은 추가로: `git -C ~/dotfiles config receive.denyCurrentBranch updateInstead` (config repo에도 동일)
- `--machine`은 해당 머신의 `apps` 목록을 설치하고 선택한 `agents_addition`·`zsh_addition`을 적용한 뒤 머신 이름을 로컬에 기억한다. 이후 `dotfiles apply`에는 다시 적지 않아도 된다.
- secrets가 필요한 머신이면 `~/.zshrc.d/secrets.zsh`를 수동으로 만들어준다 (동기화되지 않음)

이후 배포는 제어 머신에서:

```bash
dotfiles push --all        # 또는 dotfiles push <machine>
dotfiles status            # 머신별 배포 상태 확인
```

## Step 4: 기존 Syncthing 정리

git push 모델과 Syncthing 실시간 동기화는 **병행하면 안 된다**
(Syncthing이 파일을 나르면 원격 tree가 dirty가 되어 `git pull --ff-only`가 드리프트로 오탐).

1. 상태 확인:

```bash
bash .claude/skills/sync-setup/scripts/check-syncthing.sh
```

2. `folder=`에 dotfiles/config 폴더가 등록되어 있으면:
   - **첫 실제 push가 성공한 뒤에** 해제하도록 안내한다 (그 전에 끄면 동기화 공백)
   - 해제: Syncthing UI(http://localhost:8384)에서 해당 폴더 제거, 또는 사용자가 원하면 스크립트로 제거
   - 폴더 해제 후 Syncthing 자체를 계속 쓸지(다른 폴더용) 물어보고, 아니라면 `brew services stop syncthing`

3. `config/.stfolder`, `~/dotfiles/.stignore`가 남아 있으면 함께 정리한다.
