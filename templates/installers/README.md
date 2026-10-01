# 개인 설치 스크립트

앱의 설치 정보는 공용 `apps.json`과 개인 `config/apps.json`, 설치할 머신은 `config/machines.toml`의 `apps` 목록에 적는다. 공식 CLI 설치나 Homebrew로 처리할 수 없는 앱은 이 디렉터리의 스크립트로 설치한다.

`example.sh`를 `my-tool.sh` 같은 이름으로 복사하고 설치 코드를 작성한다. 앱 정의에 `"method": "script"`, `"path": "installers/my-tool.sh"`, `"args": ["{version}"]`을 적는다. `example.sh` 자체는 설치를 구현하기 전까지 오류로 종료한다.

현재 개인 설정의 Codex, Claude, Right Shift English는 공용 설치 방식을 사용하므로 개인 스크립트가 필요하지 않다. 이 디렉터리는 새 개인 앱을 추가할 때 사용한다.
