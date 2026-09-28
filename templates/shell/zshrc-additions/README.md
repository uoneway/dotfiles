# 머신별 추가 zsh 설정

이 디렉터리에 `.zsh` 파일을 만들고 `config/machines.toml`에서 `zsh_addition = "파일명.zsh"`로 선택한다. 공통 `zshrc`는 OS별 파일을 자동으로 읽은 뒤 이 파일을 읽고, 마지막에 동기화하지 않는 `local.zsh`를 읽는다.
