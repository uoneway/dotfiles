# 앱 설치 방법과 머신별 설치 목록 관리하기

`apps.json`은 앱을 어떻게 설치할지 정의하고, `config/machines.toml`은 어떤 머신에 설치할지 선택한다. 공용 `apps.json`에 개인 `config/apps.json`을 앱 이름별로 병합한다. 새 이름은 추가하고 같은 이름은 개인 설정에서 지정한 필드만 덮어쓴다. 카탈로그에 앱이 있어도 머신의 설치 목록에서 선택하기 전에는 자동 설치하지 않는다.

## 설치 전에 확인하기

- macOS 또는 Linux, Bash, Python 3.8 이상, 인터넷 연결이 필요하다.
- 두 CLI의 공식 설치 프로그램은 `curl` 또는 `wget`을 사용한다.
- Right Shift English는 macOS 13 이상과 Xcode Command Line Tools의 `swiftc`, `codesign`이 필요하다. 로그인한 사용자 세션에서 자동 실행을 등록한다. GUI 세션이 없는 Mac에서는 이 앱을 비활성화한다.
- 로그인 정보와 접근성 권한은 동기화하지 않는다. 각 머신에서 로그인하고 권한을 허용한다.

## 설치할 프로그램과 버전 선택하기

전체 설치 정책을 확인한 뒤 실행한다.

```bash
dotfiles install --dry-run
dotfiles install
```

설정 파일의 버전 고정을 이번 실행에서 무시하려면 `--latest`를 사용한다. 비활성화한 도구는 기본 전체 설치에서 계속 제외한다.

```bash
dotfiles install --latest
dotfiles install codex,claude --latest
```

특정 버전을 설치하려면 `--version TOOL=VERSION`을 사용한다. 여러 도구를 지정할 때는 옵션을 반복한다.

```bash
dotfiles install codex --version codex=0.159.2
dotfiles install codex,claude --version codex=0.159.2 --version claude=2.1.277
dotfiles install right-shift-english --version right-shift-english=1.0.0
```

`--latest`와 `--version`은 함께 사용할 수 없다. 지정 버전이 설치되어 있으면 CLI를 다시 다운로드하지 않는다. `latest`는 매 실행마다 공식 최신 버전을 조회하고, 설치 버전과 다를 때 업데이트한다. 지정 버전이 더 낮으면 해당 버전으로 전환한다.

## 설치 정보가 있는 파일 찾기

| 파일 | 저장소 | 역할 |
|---|---|---|
| `apps.json` | 공용 dotfiles | 자주 쓰는 앱의 설치 방법과 기본 버전 |
| `config/apps.json` | 개인 설정 | 새 앱 추가, 공용 앱의 설치 정보나 버전 덮어쓰기 |
| `config/machines.toml` | 개인 설정 | 로컬 전용 설정, 등록 머신의 공통 기본값과 머신별 설정 |
| `config/installers/` | 개인 설정 | `script` 방식으로 선택하는 개인 설치 스크립트 |
| `templates/apps.json` | 공용 dotfiles | 개인 앱 추가와 부분 덮어쓰기 예시. 런타임 카탈로그로 읽지 않음 |

공용 카탈로그에는 Codex, Claude, Right Shift English와 Homebrew로 설치하는 ripgrep, jq, fd, fzf, git, tmux, neovim, Visual Studio Code가 있다. Homebrew 설치 여부는 머신의 목록에서 선택한다.

병합한 전체 카탈로그와 이번 머신의 설치 목록을 각각 확인한다.

```bash
dotfiles install --catalog
dotfiles install --dry-run
```

`--catalog`는 설치 없이 병합된 정의를 JSON으로 출력한다. 머신 이름이나 설치 옵션과 함께 사용할 수 없다.

## 개인 앱 추가와 필드 덮어쓰기

개인 파일이 없으면 공용 카탈로그를 그대로 사용한다. 개인 파일이 `{}`이면 공용 앱을 유지한다. 개인 파일에 적지 않은 앱도 카탈로그에 남는다. 앱을 새로 추가하려면 설치에 필요한 필드를 모두 적는다. 같은 이름의 공용 앱을 바꾸려면 변경할 필드만 적는다.

```json
{
  "codex": {
    "version": "0.159.2"
  },
  "claude": {
    "version": "latest"
  },
  "my-tool": {
    "method": "script",
    "version": "1.2.3",
    "path": "installers/my-tool.sh",
    "interpreter": "bash",
    "args": ["{version}"]
  }
}
```

이 예시에서 Codex는 공용 설치 주소와 방식을 유지하고 버전만 고정한다. Claude는 최신 버전을 사용한다. `my-tool`은 개인 카탈로그에 추가된다. 앱을 실제로 자동 설치할 머신은 `machines.toml`에서 선택한다.

병합 규칙은 다음과 같다.

- 새 앱 이름은 공용 목록 뒤에 추가한다.
- 같은 앱 이름의 객체는 필드별로 병합한다. 개인 파일에 없는 필드는 공용 값을 유지한다.
- 배열은 개인 배열로 교체한다. 공용 배열과 이어 붙이지 않는다.
- `method`를 바꾸면 이전 설치 방식의 전용 필드는 제거한다. 새 방식에 필요한 필드를 함께 적어야 한다.
- `enabled: false`는 해당 앱을 모든 설치 명령에서 제외한다. 이미 설치한 프로그램을 제거하지 않는다.

이전 문자열 형식(`"codex": "latest"`, `"claude": false)도 각각 버전 덮어쓰기와 비활성화로 읽는다. 이전 `components` 필드는 호환 목적으로 무시한다. 새 설정에는 사용하지 않는다.

`templates/apps.json`에는 부분 덮어쓰기와 비활성 개인 스크립트 예시가 있다. JSON에는 주석을 넣을 수 없으므로 설명은 `description` 필드에 적었다. 기존 개인 파일이 있으면 필요한 항목만 옮긴다. 새 머신의 초기 설정 복사는 개인 앱 파일과 `installers/` 골격도 만든다.

## 머신별 설치 앱 선택하기

설치 대상은 `config/machines.toml`의 `apps` 배열에 적는다. 앱 이름은 병합된 카탈로그의 키와 같아야 한다.

```toml
# 이름을 지정하지 않은 로컬 실행 전용
[local]
apps = ["codex", "claude", "right-shift-english"]

# 등록된 머신이 생략한 필드에 적용하는 공통 기본 설정
[defaults]
components = "shell,claude,codex"
apps = ["codex", "claude"]

# SSH 배포 대상 서버
[machines.work-server]
host = "work-server"
apps = ["codex", "claude", "ripgrep", "jq"]

# 셸 설정만 적용하고 앱은 자동 설치하지 않는 서버
[machines.shell-only]
host = "shell-only"
components = "shell"
apps = []
```

`[local]`은 이름을 지정하지 않은 로컬 실행 전용 설정이다. `[defaults]`를 상속하지 않는다. `components`, `apps`, `agents_addition`, `zsh_addition`을 로컬용으로 지정할 수 있다. `local.apps`는 로컬 설치 목록이다. `[local]`이나 그 안의 `apps`가 없으면 로컬 앱 자동 설치는 없다.

`[defaults]`는 등록된 머신이 생략한 설정의 공통 기본값이다. 앱 외 설정도 지정할 수 있다.

| 필드 | 의미 |
|---|---|
| `components` | 적용할 설정 구성 요소. 예: `"shell,claude,codex"` |
| `apps` | 설치할 앱 이름 배열 |
| `transport` | 배포 방식: `"hub"` 또는 `"direct"` |
| `path` | 원격 dotfiles 경로 |
| `agents_addition` | 추가 인스트럭션 파일 이름 |
| `zsh_addition` | 추가 셸 설정 파일 이름 |

`host`는 머신별 식별 정보이므로 각 `[machines.<이름>]`에 적는다. 머신에 명시한 필드는 공통 기본값을 교체한다. 배열은 이어 붙이지 않고 교체한다. `agents_addition = ""` 또는 `zsh_addition = ""`는 상속한 추가 파일을 끈다. 머신 목록 조회, `push`, `apply`, 앱 설치가 같은 병합 결과를 읽는다.

`apply` 명령에 구성 요소를 직접 전달하면 이번 실행에서는 그 값을 우선한다. 구성 요소를 전달하지 않으면 선택한 머신의 설정을 사용하고, 값이 없으면 기존 설정 파일을 보고 자동 감지한다.

등록된 머신에서 `apps`를 생략하면 `defaults.apps`를 상속한다. 현재 템플릿은 두 CLI를 기본 설치 목록으로 선택한다. 기본값과 같은 `components`나 `apps`는 머신 항목에서 생략한다. `[defaults]`나 그 안의 `apps`가 없으면 기본값은 빈 목록이다. 머신에 `apps`를 명시하면 기본 목록을 교체하고, `apps = []`는 해당 머신의 자동 설치를 끈다. 로컬 목록을 등록된 머신에 상속하지 않는다.

개인 앱도 해당 배열에 이름을 추가한다. 선택된 목록에 중복되거나 카탈로그에 없는 이름이 있으면 설치 전에 실패한다.

머신 선택은 `--machine` → `DOTFILES_MACHINE` → 로컬 `~/.local/state/dotfiles/machine` 기록 순서다. 이름이 없으면 `local.apps`를 사용한다. `apply --machine 이름`이 성공하면 머신 이름을 로컬에 기록한다. 이 기록은 설정 저장소에 넣지 않는다.

```bash
dotfiles install --machine work-server --dry-run
dotfiles apply --machine work-server
```

`install --machine`은 그 머신의 정책을 선택해 **현재 머신에서** 실행한다. SSH 설치 명령이 아니다. 다른 머신에 실제 배포하려면 기존 `dotfiles push work-server`를 사용한다. 원격 `apply --machine work-server`가 대상 머신의 목록을 읽는다.

이동형 랩탑은 SSH 배포 대상으로 등록하지 않고 `local.apps`를 사용한다. 기존 `dotfiles pull` 흐름을 유지한다. 현재 OS가 앱의 `platforms`에 없으면 자동 목록에서 제외한다.

앱 이름을 명령에 직접 지정하면 이번 실행에서는 머신의 `apps` 목록을 대체한다. 비활성 앱은 계속 제외한다. 설치 목록과 버전을 계속 유지하려면 개인 파일을 수정해 커밋한다.

```bash
dotfiles install jq --dry-run
dotfiles install codex --version codex=0.159.2
```

## 설치 방법 지정하기

항목 이름은 사용자가 정한다. 소문자, 숫자, `_`, `-`를 사용할 수 있고 첫 글자는 소문자 또는 숫자여야 한다. `official` 방식의 두 전용 어댑터는 실행 파일 이름을 관리하므로 각각 `codex`, `claude`라는 이름을 사용한다. 다른 프로그램은 `homebrew` 또는 `script`로 추가하면 공용 코드 수정이 필요 없다.

### 모든 방식의 공통 필드

| 필드 | 필수 여부 | 기본값과 의미 |
|---|---|---|
| `method` | 필수 | `official`, `homebrew`, `script`, `right-shift-app` 중 선택 |
| `version` | 선택 | `latest`. 지정 버전은 `x.y.z` 또는 `x.y.z-preview.1` 형식 |
| `enabled` | 선택 | `true`. `false`면 모든 설치 명령에서 제외 |
| `platforms` | 선택 | `["Darwin", "Linux"]`. 대상 OS 목록 |
| `description` | 선택 | 설명 문자열. 설치 동작에는 사용하지 않음 |

`--dry-run`은 선택한 버전, 설치 방식, 설치 출처를 출력한다. 다운로드나 실제 설치는 하지 않는다. 정의되지 않은 이름, 알 수 없는 필드, 잘못된 버전은 오류로 처리한다.

### 공식 CLI 설치 스크립트

`official`은 Codex와 Claude의 설치 결과 확인과 자동 업데이트 제어를 처리하는 전용 어댑터다. URL만 바꿔 다른 프로그램을 설치하는 범용 방식은 아니다. 다른 프로그램의 설치 스크립트는 `script`를 사용한다.

| 필드 | 필수 여부 | 의미 |
|---|---|---|
| `adapter` | 필수 | `codex` 또는 `claude` |
| `installer_url` | 필수 | HTTPS 설치 스크립트 주소 |
| `latest_urls` | 필수 | HTTPS 최신 버전 조회 주소 목록. 앞 주소가 실패하거나 잘못된 값을 반환하면 다음 주소 사용 |
| `latest_format` | 필수 | `text`: 응답 본문이 버전 문자열. `tag_name`: JSON의 `tag_name` 값 |
| `tag_prefix` | 선택 | 태그 앞에서 제거할 문자열. 기본값은 빈 문자열 |

CLI별 전체 정의는 공용 `apps.json`에 있다. 설치 스크립트의 호출 규약과 바이너리 경로는 어댑터가 처리하고, 사용할 어댑터와 다운로드 출처는 개인 설정에서 고른다.

### Homebrew formula와 cask

Homebrew를 먼저 설치해야 한다. 자동으로 Homebrew 자체를 설치하지 않는다. `package`는 필수이고 `kind`는 기본값 `formula` 또는 `cask`다. cask는 macOS에서만 사용한다.

```json
{
  "editor": {
    "method": "homebrew",
    "package": "visual-studio-code",
    "kind": "cask",
    "version": "latest",
    "platforms": ["Darwin"]
  }
}
```

설치 시 `brew update`로 패키지 정보를 갱신한 뒤 해당 패키지를 설치하거나 업그레이드한다. 사용자 지정 tap 패키지는 `owner/tap/name`으로 적는다. 이 방식은 [Homebrew의 패키지 설치 명령](https://docs.brew.sh/Manpage)을 사용한다.

Homebrew는 임의의 과거 `x.y.z` 버전을 설치하는 기능을 보장하지 않으므로 `version`에는 `latest`만 허용한다. 지원되는 버전 계열을 선택하려면 `package`에 `python@3.13` 같은 버전별 formula 이름을 적는다. 정확한 버전 고정이 필요하면 공식 어댑터나 개인 스크립트를 사용한다. `--version`으로 Homebrew 항목에 지정 버전을 요청하면 설치 전에 오류로 처리한다.

### 개인 설치 스크립트

개인 스크립트는 `config/installers/`에 넣고 함께 커밋한다. 초기 설정에서 이 디렉터리에 `README.md`와 `example.sh`를 복사한다. `example.sh`는 작성용 골격이며, 수정하지 않은 상태에서는 오류로 종료한다. 기존 설정에 디렉터리가 없으면 아래 명령으로 준비한다.

```bash
mkdir -p config/installers
cp templates/installers/example.sh config/installers/my-tool.sh
```

```json
{
  "my-tool": {
    "method": "script",
    "version": "1.2.3",
    "path": "installers/my-tool.sh",
    "interpreter": "bash",
    "args": ["{version}"]
  }
}
```

| 필드 | 필수 여부 | 의미 |
|---|---|---|
| `path` | 필수 | `config/` 기준 상대 경로. 절대 경로, `..`, `config/` 밖으로 나가는 심볼릭 링크는 허용하지 않음 |
| `interpreter` | 선택 | `bash`가 기본값. `sh`, `python3`도 사용 가능 |
| `args` | 선택 | 기본값 `["{version}"]`. 인자 문자열 목록에 `{version}`을 한 번 이상 포함해야 함 |

`{version}`은 `latest` 또는 선택한 지정 버전으로 치환한다. 인자는 셸 명령 문자열로 합치지 않고 각각 전달하므로 공백과 `$()`도 그대로 전달한다. 스크립트에는 `DOTFILES_APP_NAME`, `DOTFILES_APP_VERSION`, `DOTFILES_ROOT` 환경 변수도 전달한다. 스크립트는 작업 디렉터리에 의존하지 않고 이 변수나 자신의 파일 경로를 사용한다.

최신 버전 조회, 다운로드, 설치 결과 확인, 반복 실행 시 처리, 버전 고정은 개인 스크립트가 담당한다. 실패하면 0이 아닌 종료 코드를 반환해야 한다. 공용 설치 코드는 이 실패를 전달한다. 설정 파일과 스크립트가 커밋되면 다른 머신에서도 같은 방법으로 실행한다. 셸 초기화 파일을 직접 수정하는 설치 스크립트는 사용하지 않는다.

### Right Shift English 소스 빌드

`right-shift-app`은 Right Shift English를 빌드하고 로그인 실행을 등록하는 전용 방식이다. `package`에는 dotfiles 기준 상대 소스 디렉터리를 적는다. `platforms`는 반드시 `["Darwin"]`으로 지정한다.

```json
{
  "right-shift-english": {
    "method": "right-shift-app",
    "version": "latest",
    "package": "packages/right-shift-english",
    "platforms": ["Darwin"]
  }
}
```

공용 저장소의 버전별 Swift 소스와 앱 빌드 로직을 재사용한다. 개인 설정에는 설치 여부, 버전, 사용할 소스 디렉터리를 둔다.

## 설정 적용과 함께 설치하기

```bash
dotfiles apply
dotfiles apply codex,claude --latest
dotfiles apply codex --version codex=0.159.2
dotfiles apply --skip-install
```

`apply`는 머신의 `apps` 목록을 설치한 뒤 선택한 설정 구성 요소를 적용한다. `components`는 셸과 AI 도구 설정의 적용 범위이고 앱 목록을 결정하지 않는다. 일부 구성 요소만 적용해도 해당 머신의 앱 목록을 설치한다. 지원하지 않는 OS에서 앱 이름을 명시적으로 선택하면 오류를 반환한다.

설치 실패 시 `apply`는 설정 연결 전에 중단하고 적용 성공 기록을 갱신하지 않는다. 설치를 건너뛰려면 `--skip-install`을 사용한다. 이 옵션은 버전 선택 옵션과 함께 사용할 수 없다.

새 머신에 AI CLI가 없어도 설치를 시작할 수 있다.

```bash
bash ~/dotfiles/install.sh --apps --dry-run
bash ~/dotfiles/install.sh --apps
bash ~/dotfiles/install.sh --setup
```

`--setup`은 개인 설정 저장소를 `~/dotfiles/config`에 준비한 뒤 실행한다. `push`와 `pull`은 대상 머신의 `apply`를 실행하므로 병합된 앱 정의와 커밋된 `machines.toml` 설치 목록을 따른다.

## 버전 고정과 자동 업데이트

Codex는 [공식 설치 프로그램](https://learn.chatgpt.com/docs/codex/cli)에 해석한 버전을 `--release`로 전달한다. dotfiles가 `latest`를 조회하고 적용할 때마다 갱신한다.

Claude Code는 [공식 설치 프로그램](https://code.claude.com/docs/en/setup)에 버전을 전달한다. dotfiles의 `~/.local/bin/claude` 실행기는 해당 버전의 공식 바이너리를 호출한다. 지정 버전에서는 `DISABLE_AUTOUPDATER=1`로 자동 업데이트를 끄고, `latest`로 돌아가면 다시 허용한다. 기존 npm·Homebrew 설치는 자동 제거하지 않는다. 다른 설치가 PATH에서 먼저 발견되면 경고를 출력하므로 `~/.local/bin`을 먼저 찾도록 설정한다.

## Right Shift English 설치와 권한 허용

Right Shift English의 `latest`는 **현재 dotfiles 커밋에 포함된 최신 앱 소스 버전**이다. 설정의 `package` 디렉터리 안에서 `latest` 파일이 버전을 가리키고, 각 버전 디렉터리에 `ShiftEnglish.swift` 소스를 보관한다. 첫 버전은 `1.0.0`이다. 외부 앱 릴리스를 조회하는 방식은 아직 사용하지 않는다. 새 버전을 추가할 때는 이전 버전의 소스를 수정하지 않고 새 디렉터리와 `latest`를 커밋한다. 포함되지 않은 버전을 요청하면 설치 전에 실패한다.

설치 프로그램은 대상 Mac에서 앱을 빌드하고 서명을 검증한 뒤 `~/Applications/Right Shift English.app`에 설치한다. 빌드 실패 시 기존 앱을 유지한다. 같은 버전과 소스가 설치되어 있으면 다시 빌드하지 않는다. 앱과 자동 실행 등록은 로컬에 남긴다.

앱 설치 후 macOS의 **시스템 설정 → 개인정보 보호 및 보안 → 기기 제어 및 데이터 접근**에서 Right Shift English를 허용한다. OS 버전에 따라 이 항목은 **손쉬운 사용**으로 표시된다. 허용한 뒤 다음 명령을 다시 실행한다.

```bash
dotfiles install right-shift-english
```

로컬 서명으로 빌드한 앱은 업데이트 시 접근성 등록을 다시 허용해야 할 수 있다. 권한이 없을 때 설치 완료와 실행 가능 상태를 구분해 안내한다. 자동 실행 등록은 권한 오류로 종료한 프로세스를 계속 재시작하지 않고, 비정상 종료 시에만 재시작한다.

앱은 한글 두벌식과 ABC 입력기를 사용한다. 오른쪽 Shift 기능은 Karabiner 없이 동작한다. 현재 Caps Lock·오른쪽 Option의 한·영 전환은 기존 Karabiner의 F18 매핑을 사용한다. 입력기 상태는 F18 전환을 기준으로 유지하므로 메뉴 막대에서 바꾸면 저장 상태로 돌아갈 수 있다.

## 검증 실행하기

```bash
python3 -m unittest discover -s tests -v
bash -n bin/dotfiles install.sh
```

테스트는 CLI 설치 호출을 대체하고, Mac에서는 임시 폴더에 실제 앱을 빌드해 버전과 서명을 검증한다. 사용자 앱이나 CLI를 교체하지 않고, 자동 실행 호출도 대체한다.
