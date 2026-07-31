# AGENTS.md

`~/dotfiles`에서 작업할 때 규칙의 기준이 되는 파일이다. `CLAUDE.md`는 이 파일을 가리키는 포인터만 두고, 규칙은 여기 한 곳에만 쓴다.

(참고: `config/ai/AGENTS.md`는 이것과 다른 파일이다 — 그건 모든 도구·모든 프로젝트에 배포되는 글로벌 인스트럭션이고, 이 파일은 dotfiles 레포 자체에서 작업할 때만 적용되는 규칙이다.)

## 레포 구조

- `dotfiles/` (이 레포, public) — CLI(`bin/dotfiles`)와 `templates/`만 담은 프레임워크.
- `dotfiles/config/` (private, 별도 git 레포 `dotfiles-config`) — 실제 개인 설정. `**dotfiles`와는 완전히 별개의 git 히스토리를 가진 중첩 레포**다. 항상 `git status`와 `git -C config status`를 각각 확인할 것 — 하나만 커밋하고 다른 하나를 잊기 쉽다.
- 전체 아키텍처(심링크 vs 병합 대상 표, 동기화 범위)는 `README.md`가 기준 문서다. 여기서는 그걸 반복하지 않고 작업 규칙만 다룬다.

## 핵심 원칙

1. **내 의도(취향·정책)는 동기화, 머신 상태(런타임 기록·자격증명·머신 경로)는 로컬에 남긴다.** `config/`에 두는 것은 전부 모든 머신에 배포된다.
2. **배포되는 것은 항상 커밋이다.** `dotfiles push`는 로컬(`dotfiles` 또는 `config`)이 dirty면 중단한다.
3. **원격이 dirty하면 건너뛰고 보고만 한다.** `--force` 없이는 절대 덮어쓰지 않는다. 같은 이유로 `dotfiles status`는 읽기 전용이며 자동 복구를 하지 않는다 — 판정은 하되 손대지는 않는다.

## 하지 말아야 할 것 (실제로 반복됐던 실수)

- `**config/shell/zshrc` / `shell/bashrc`에 직접 append하지 않는다.** 이 파일들은 모든 머신에 심링크되는 git 관리 대상이다. `nvm`, `pyenv`, `rustup`, 각종 CLI 설치 스크립트가 로그인 셸 rc 파일에 자동으로 PATH/init 블록을 추가하는 경우가 흔한데, 이게 심링크를 타고 이 레포에 그대로 들어와 drift로 잡힌다. 설치 스크립트를 실행하기 전에 결과가 `~/.zshrc`에 append되는지 확인하고, **머신 전용 내용은 `~/.zshrc.d/local.zsh`(또는 bash라면 `~/.bashrc.d/local.bash`)로 옮길 것** — 이 파일들은 real file이며 절대 동기화 대상이 아니다. 이미 append돼버린 걸 발견했다면 `config/shell/zshrc` 끝의 경고 배너 바로 아래에 있을 확률이 높다.
- `**settings.json` / `config.toml`을 직접 편집하지 않는다.** 이건 병합 결과물이다. 바꾸고 싶으면 `config/ai/claude/settings.base.json` / `config/ai/codex/config.base.toml`의 base 키를 고치고 `dotfiles apply`로 재병합시킨다. 직접 고치면 다음 apply 때 base 키와 충돌하거나, base에서 삭제한 키가 라이브 파일에 잔존하는 알려진 한계에 부딪힌다.
- **secrets를 `config/`에 커밋하지 않는다.** `dotfiles push`가 커밋 전 secret 스캔을 돌리지만 이건 백스톱이지 전부가 아니다. API 키·토큰은 각 머신의 `~/.zshrc.d/secrets.zsh`(동기화 제외)에 둔다.
- `**bin/dotfiles`(프레임워크 코드) 변경은 feature 브랜치로 하되, push 전에 반드시 `main`으로 머지한다.** hub transport 원격은 전부 자기 `main`만 pull한다. 브랜치에 커밋만 쌓아두고 `dotfiles push`를 돌리면 origin에 브랜치가 백업될 뿐 원격엔 아무 것도 배포되지 않는다 — push 전에 `git branch --show-current`로 확인하는 습관을 들인다.

## 배포 워크플로우

```
config/ 편집 (또는 bin/dotfiles 수정) → 해당 레포에 커밋
  → dotfiles push --all         # 각 머신: git pull → apply → verify
  → dotfiles status             # 배포 상태·drift 확인 (읽기 전용)
```

- `dotfiles status` / `dotfiles status --json`: STATE(`synced` / `behind N` / `drift` / `not bootstrapped` / `unreachable(사유)`)와 APPLIED(`ok` / `stale` / `never`, 마지막 적용 후 경과 시간)를 판정해서 보여준다. 원격당 ssh 왕복 1회로 필요한 정보를 전부 모으고, ControlMaster 소켓으로 반복 접속을 가속한다.
- `~/.local/state/dotfiles/applied`: apply 성공 시 `<fw-sha> <cfg-sha> <epoch>`를 기록한다. "pull은 됐는데 apply가 실패/누락됨"을 감지하는 유일한 근거이므로, 이 기록 로직(`cmd_apply` 끝부분)을 건드릴 때는 신중히.
- 새 기능/다음 작업은 `docs/backlog.md`(이 레포, public)에 우선순위(1/2/3순위)로 적어 세션 간 핸드오프한다. 개인 설정 관련 메모가 아니라 프레임워크 자체의 로드맵이라 public 레포 쪽이 맞는 자리다.

