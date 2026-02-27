---
name: uninstall
description: "dotfiles 심링크 제거 및 원본 복원. uninstall, remove, restore 요청 시 트리거."
model: sonnet
allowed-tools:
  - Bash(bash .claude/skills/uninstall/scripts/*)
  - Bash(bash .claude/skills/setup/scripts/verify.sh)
  - AskUserQuestion
  - Read
  - Write
  - Edit
---

# /uninstall — dotfiles 심링크 제거

dotfiles가 생성한 심링크를 제거하고, 설치 이전 상태로 복원한다.
단순히 백업을 되돌리는 것이 아니라, dotfiles 사용 중 변경한 설정을 잃지 않도록 비교 및 병합 과정을 거친다.

## 사전 조건

- 현재 디렉토리가 `~/dotfiles` (또는 dotfiles 레포 루트)인지 확인

## Step 1: 현재 상태 확인

```bash
bash .claude/skills/setup/scripts/verify.sh
```

심링크된 항목들을 파악한다.

## Step 2: 사용자 확인

AskUserQuestion으로 범위를 확인:

- **전체 제거**: 모든 dotfiles 심링크 제거
- **선택 제거**: 특정 도구만 선택하여 제거 (claude, codex, gemini, shell)

## Step 3: 변경사항 비교

**이 단계가 핵심이다.** `backup/` 폴더에 저장된 원본이 있는 항목마다, dotfiles 사용 기간 중 `config/` 파일에 반영된 변경사항을 확인한다.

백업은 `dotfiles/backup/` 아래에 홈 디렉토리 구조를 미러링하여 저장되어 있다:
- `backup/.zshrc` — 설치 이전의 `~/.zshrc`
- `backup/.claude/settings.json` — 설치 이전의 `~/.claude/settings.json`
- 등등

각 백업 파일에 대해:

1. `backup/` 파일(설치 이전 원본)과 대응하는 `config/` 파일(현재 설정)을 읽는다

2. 두 파일을 비교하여 차이점을 분석한다:
   - 예: `backup/.zshrc` vs `config/shell/zshrc`
   - 예: `backup/.claude/settings.json` vs `config/ai/claude/settings.json`

3. 차이가 있으면 사용자에게 보여주고 선택을 묻는다:

   **차이가 없는 경우:**
   "원본과 현재 설정이 동일합니다. 원본을 복원합니다."

   **차이가 있는 경우:**
   변경된 내용을 요약해서 보여주고 AskUserQuestion:
   - **원본 복원**: 설치 이전 파일을 그대로 되돌립니다 (dotfiles에서 변경한 내용은 사라집니다)
   - **현재 설정 유지**: 심링크만 제거하고, `config/` 파일 내용을 실제 파일로 복사합니다
   - **병합**: 두 파일의 차이를 보여주고 어떤 부분을 살릴지 직접 선택합니다

4. 백업이 없는 항목은 심링크만 제거한다 (도구가 기본값을 사용하게 됨)

## Step 4: 심링크 제거 및 복원 실행

Step 3에서 사용자가 결정한 방식에 따라 각 항목을 처리한다:

- **원본 복원** 선택 항목:
  ```bash
  bash .claude/skills/uninstall/scripts/unlink.sh <도구> --restore
  ```

- **현재 설정 유지** 선택 항목:
  ```bash
  bash .claude/skills/uninstall/scripts/unlink.sh <도구> --keep
  ```

- **심링크만 제거** (백업 없음):
  ```bash
  bash .claude/skills/uninstall/scripts/unlink.sh <도구> --remove-only
  ```

- **병합** 선택 항목:
  사용자와 대화하며 `backup/` 원본과 `config/` 현재 설정을 합친 파일을 생성하여 해당 위치에 저장한다.

## Step 5: 결과 보고

처리 결과를 항목별로 요약한다:
- 원본 복원된 항목
- 현재 설정이 유지된 항목
- 병합된 항목
- 심링크만 제거된 항목 (백업 없음)

> **참고**: `config/` 디렉토리는 삭제하지 않는다. 사용자의 설정이 그대로 보존된다.
> `backup/` 폴더도 그대로 남는다. 필요 없으면 수동으로 삭제할 수 있다.
> 다시 설치하려면 `/setup`을 실행하면 된다.
