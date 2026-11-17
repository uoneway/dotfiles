# 기존 UI 개선 스킬 제안

조사일: 2026-11-17. 상태: 제안, 미구현·미배포.

기존 화면을 사용자 과업에 맞게 개선하는 `ui-improve` 스킬을 제안한다. 사람이 경험의 방향과 중요한 경계를 정하면 에이전트가 실제 화면과 코드를 조사하고, 위임 범위에서 개선·검증까지 맡는다. 기존 `align`과 `prototype`을 필요할 때 재사용한다.

이 문서는 스킬의 범위와 설계를 결정하기 위한 조사 기록이다. 웹 UI를 주된 조사 대상으로 삼았다. 네이티브 앱에도 과업·증거·위임 원칙은 적용할 수 있지만, 플랫폼별 구현 규칙은 별도 확인해야 한다.

## 판단 근거와 한계

로컬 Agent Workflow Protocol의 원칙·정보 소유권·실행 흐름과 `align`, `prototype`, `skill-writer`를 읽었다. 공개 스킬은 실행 지침과 관련 참조 파일을 읽어 비교했다. 실제 프로젝트에 설치하거나 같은 과제로 성능을 비교하지 않았다. 아래의 적합성 평가는 문서에서 추론한 설계 판단이며, 효과가 검증됐다는 뜻은 아니다.

별도 스킬을 제안하는 이유는 기존 `prototype`이 대안을 보고 선택하는 일에 집중하기 때문이다. 반복적인 기존 UI 개선에는 현재 경험의 문제를 관찰하고, 중요한 문제를 선택하고, 수정 결과를 실행해서 확인하는 흐름이 추가로 필요하다. 실제 사용에서 기본 모델과 차이가 없다면 스킬을 줄이거나 폐기한다.

## 원칙을 화면에서 확인할 질문으로 바꾸기

| 근거 | 스킬에 반영할 질문과 행동 | 적용 경계 |
| --- | --- | --- |
| GOV.UK Government Design Principles | 누가 어떤 상황에서 무엇을 끝내려는가? 기존 피드백과 데이터를 읽고 개선할 과업을 정한다. | 에이전트의 추측을 사용자 조사 결과로 표현하지 않는다. |
| Nielsen의 사용성 휴리스틱 | 현재 상태와 다음 행동을 알 수 있는가? 오류를 예방하고 복구할 수 있는가? 익숙한 용어와 조작을 쓰는가? | 휴리스틱은 문제를 찾는 관점이다. 항목 점수의 합으로 사용성을 입증하지 않는다. |
| NN/g 시각 디자인 원칙 | 중요도와 시각적 강조가 맞는가? 크기·대비·근접성·균형으로 읽는 순서와 그룹이 드러나는가? | 장식이나 특정 유행을 모든 화면에 강제하지 않는다. |
| WCAG 2.2 및 WAI-ARIA APG | 키보드 조작, 보이는 초점, 이름·역할·상태, 대비, 확대와 입력 오류를 실제로 확인한다. | 적용 기준과 예외를 원문에서 확인한다. 자동 검사 통과만으로 전체 준수를 선언하지 않는다. |
| GOV.UK Design System Patterns | 입력·오류 복구·확인 같은 과업에 검증된 패턴을 먼저 검토한다. | 영국 공공서비스의 문구와 구조를 다른 제품에 그대로 이식하지 않는다. |
| 기존 디자인 시스템과 실제 화면 | 토큰·컴포넌트·플랫폼 관례를 조사하고 기존 맥락에서 개선한다. | 기존 패턴도 문제의 원인이면 수정 후보가 된다. 큰 방향 전환은 합의 범위를 확인한다. |

규칙의 종류를 구분해야 한다. 접근성 성공 기준, 경험적 휴리스틱, 제품별 취향은 서로 다른 근거다. 예를 들어 클릭 영역의 권장 크기와 WCAG AA의 최소 기준을 같은 규칙으로 적으면 안 된다. 한국어 UI에 영어 Title Case 규칙을 적용해서도 안 된다.

## 공개 스킬 비교

| 스킬 | 원문에서 확인한 특징 | 가져올 요소 | 그대로 채택하지 않을 요소 |
| --- | --- | --- | --- |
| Anthropic `frontend-design` | 주제·대상·실제 콘텐츠에서 시각적 방향을 만들고 타이포그래피·레이아웃을 의도적으로 선택한다. 렌더링 화면의 자기평가를 권한다. | 제품 맥락에서 시각적 선택을 설명하고 화면으로 확인하는 방식 | 시각적 독창성을 모든 개선의 최우선 목표로 두는 방식 |
| Vercel `web-design-guidelines` | 최신 규칙을 읽고 지정 파일을 검사해 위치가 있는 지적을 출력한다. | 시맨틱 HTML, 초점, 입력, 긴 콘텐츠, 반응형과 상태 점검 | 코드 검사만으로 경험 개선 완료를 판정하는 방식. 문체·수치·스택 선호를 보편 규칙으로 취급하는 방식 |
| Impeccable | 화면 목적에 맞춰 표현 강도를 조절한다. `critique`는 시각적 판단과 탐지 결과를 분리하고, `audit`는 기술 품질을 다룬다. | 기존 화면 조사, 목적에 맞는 표현, 시각 판단과 측정 결과의 구분 | critique마다 독립 에이전트·점수표·스냅샷을 요구하는 절차. 독립 검토는 판단 편향의 비용이 클 때 선택한다. |
| UI UX Pro Max | 디자인·제품·스택 지식을 검색하고 구체적인 요청에는 작은 검색 범위를 선택한다. | 필요할 때만 관련 지식을 여는 구조, 대상과 스택을 확인하는 방식 | 초기 버전부터 대형 검색 DB를 유지하는 비용. 코드의 토큰과 별도로 디자인 값 전체를 문서에 복제하는 방식 |

Impeccable이 기존 UI 개선과 가장 가깝다. 다만 그대로 도입하면 현재 프로토콜보다 많은 고정 절차와 기록이 생긴다. UI UX Pro Max도 범위가 넓지만, 현재 필요한 것은 스타일 추천 데이터베이스보다 문제를 선택하고 완료를 입증하는 흐름이라는 판단이다.

## Agent Workflow Protocol을 반영한 실행 방식

| 프로토콜의 관점 | `ui-improve`의 행동 |
| --- | --- |
| 사람은 방향, 에이전트는 실행 | 대상 사용자·주요 과업·지킬 경험·위임 범위를 기존 대화에서 복원한다. 환경이 답할 질문은 직접 조사한다. |
| 현재 사실은 실제 원천에서 확인 | 실행 화면, 코드, 토큰, 컴포넌트, 기존 피드백을 읽는다. 스크린샷만 있으면 동작을 확인하지 못했다고 밝힌다. |
| 합의는 매번의 승인 의식이 아님 | 개선 요청이면 필요한 수정과 검증까지 진행한다. 평가 요청이면 근거와 추천으로 끝낸다. |
| 중요한 미결정만 사람에게 돌림 | 브랜딩 교체, 정보 구조의 큰 변경, 사용자 약속 변경처럼 합의된 경계를 바꾸는 선택만 다시 맞춘다. 취향을 위임받았다면 추천을 정하고 실행한다. |
| 증거가 완료를 결정 | 동일한 과업·데이터·화면 조건에서 전후를 비교한다. 시각 확인과 동작 확인을 구분한다. |
| 필요한 기록만 보존 | 코드로 복원할 수 없는 선택 이유와 외부 증거만 남긴다. 색상·간격·현재 상태를 별도 문서에 수동 복제하지 않는다. |
| 모델의 약점을 영구 절차로 만들지 않음 | 실사용에서 효과가 확인된 지침만 유지한다. 모든 작업에 다안 생성·독립 감사·전체 점수표를 요구하지 않는다. |

## 제안하는 스킬의 범위

이름은 `ui-improve`로 한다. 호출 의도는 기존 화면·흐름의 사용성, 정보 위계, 시각적 완성도를 검토하거나 개선하는 요청이다. 새 제품의 방향 탐색은 `align`, 보고 선택해야 할 대안은 `prototype`이 맡는다. 좁은 CSS 수정은 전체 평가로 확대하지 않는다.

기본 작업 흐름은 다음과 같다. 단계마다 승인받는 절차는 아니다.

1. 개선할 과업과 현재 화면을 확인한다. 실제 데이터, 주변 화면, 현재 디자인 시스템을 함께 읽는다.
2. 관찰한 현상과 예상되는 사용자 영향을 연결한다. 실행으로 확인한 결함, 휴리스틱에 따른 가설, 시각적 취향을 구분한다.
3. 과업 방해 정도·발생 범위·근거의 강도·변경 비용으로 우선순위를 정한다. 가짜 정밀도의 종합 점수는 만들지 않는다.
4. 요청이 실행이면 중요한 문제를 수정한다. 방향이 열려 있고 눈으로 비교해야 판단할 수 있을 때만 시각적 대안을 만든다.
5. 변경한 경험을 실제로 확인한다. 관련 화면 크기, 키보드, 로딩·빈 결과·오류·긴 콘텐츠 등 변경이 영향을 주는 조건을 고른다.
6. 무엇이 달라졌는지, 어떤 증거가 있는지, 무엇을 확인하지 못했는지 보고한다. 새로운 실패나 위험이 없고 필요한 검증이 끝나면 마친다.

검증 예시: 설정 폼에서 저장 오류가 나도 입력값을 유지하고, 오류 항목과 복구 방법을 보여주며, 키보드로 수정 후 다시 저장할 수 있는지 확인한다. 화면 전후 비교는 위계와 간격을 보여주지만 오류 복구 동작을 입증하지는 못한다. 사용자 실험을 하지 않았다면 완료율이나 만족도가 상승했다고 주장하지 않는다.

## 최소 파일 구성과 평가 방법

초기 구성은 `SKILL.md`와 필요할 때 읽을 `references/review-lenses.md`로 충분하다. 본문에는 목적·작업 범위·증거·완료 조건을 둔다. 참조 파일에는 과업 흐름, 시각적 위계, 콘텐츠와 상태, 접근성을 어떤 상황에서 볼지 적는다. 플랫폼별 참조와 자동 검사 스크립트는 실제 반복 비용이 드러날 때 추가한다.

기존 화면 개선 요청은 자동 호출 후보로 두되, 사소한 스타일 수정마다 전체 절차가 실행되지 않도록 설명을 좁힌다. 디자인 문제를 근거와 연결하고 실제 결과로 확인하는 판단을 이 스킬이 소유한다. 다른 스킬은 그 판단에 필요할 때 호출한다.

작성 후에는 같은 모델·환경·시작 코드·사용자 요청으로 스킬 유무를 비교한다. 설정 폼의 복구 흐름, 밀도 높은 목록의 위계, 브랜드를 유지하는 국소 개선이 대표 과제다. 과업 성공 여부, 기존 동작 보존, 근거 없는 주장, 불필요한 승인 중단을 관찰한다. 시각 선호는 가능하면 결과의 출처를 가리고 사람이 비교한다. 차이가 확인되지 않는 지침은 삭제한다.

아직 이 비교를 실행하지 않았다. 스킬 전체 작성·설치·프로토콜 수정도 이번 조사에 포함하지 않았다. 실제 과제에서 Impeccable을 좁혀 쓰는 방식이 더 적은 지침으로 같은 결과를 낸다면 새 스킬 제안을 재검토한다. 요구가 신규 랜딩페이지 제작이나 네이티브 UI 중심으로 바뀌어도 범위를 다시 정해야 한다.

## 출처 목록

모든 외부 출처의 접근일은 2026-11-17이다. 아래 링크는 각 자료의 소유자가 제공하는 원문이다. 문서와 코드를 읽었으며 공개 스킬의 런타임은 실행하지 않았다. 외부 원문 사본은 저장하지 않았다. 변경되는 GitHub 자료는 아래 확인 지점 또는 링크에서 재조사한다.

| 출처·소유자 | 정확한 위치 | 확인 지점·지원하는 주장 |
| --- | --- | --- |
| Agent Workflow Protocol · uoneway | `/Users/hangil/Project/agent-workflow-protocol/AGENT_WORKFLOW_PROTOCOL.md` | 로컬 HEAD `b4ce3c54d63d3f24e4f97264767c2226fbffe186`. Principles, Information Ownership, Workflow를 읽음. 위임·검증·기록 경계의 기준. |
| 로컬 스킬 | `/Users/hangil/.agents/skills/align/SKILL.md`, `/Users/hangil/.agents/skills/prototype/SKILL.md`, `/Users/hangil/.agents/skills/prototype/UI.md`, `/Users/hangil/.agents/skills/skill-writer/SKILL.md` | 조사 시점 파일. 대안 탐색과 구현의 역할 구분, 작은 스킬 설계. |
| Government Design Principles · GDS/CDDO | https://www.gov.uk/guidance/government-design-principles | 페이지 갱신일 2025-04-02. 사용자 필요·데이터·맥락. |
| 10 Usability Heuristics · Jakob Nielsen/NN/g | https://www.nngroup.com/articles/ten-usability-heuristics/ | 페이지 검토일 2024-01-30. 상태·일관성·오류·복구. |
| 5 Principles of Visual Design in UX · Kelley Gordon/NN/g | https://www.nngroup.com/articles/principles-visual-design/ | 페이지 검토일 2026-09-01. 크기·위계·균형·대비·게슈탈트. |
| WCAG Quick Reference · W3C WAI | https://www.w3.org/WAI/WCAG22/quickref/ | WCAG 2.2 기준 참조. 접근성 성공 기준과 수준을 구분. |
| APG Read Me First · W3C WAI | https://www.w3.org/WAI/ARIA/apg/practices/read-me-first/ | 살아 있는 문서, 버전 고정 안 함. 시맨틱·ARIA와 지원 검증. |
| Patterns · GOV.UK Design System | https://design-system.service.gov.uk/patterns/ | 살아 있는 문서. 사용자 과업별 패턴 참조. |
| frontend-design · Anthropic | https://github.com/anthropics/skills/blob/main/skills/frontend-design/SKILL.md | main, 커밋 미고정. 주제 중심 시각 설계와 렌더링 확인. |
| web-design-guidelines · Vercel | https://github.com/vercel-labs/agent-skills/blob/main/skills/web-design-guidelines/SKILL.md | 파일 metadata 1.0.0. 파일 검사형 스킬의 범위. |
| Web Interface Guidelines · Vercel | https://github.com/vercel-labs/web-interface-guidelines/blob/main/command.md | main, 커밋 미고정. 기술 점검과 제품별 선호가 섞인 규칙. |
| Impeccable · Paul Bakaus | https://github.com/pbakaus/impeccable/blob/main/.agents/skills/impeccable/SKILL.md | metadata 4.9.2; API tree `d41d9860b0094dcb68030657da63461212835aaa`. 화면 목적·기존 맥락·렌더링 검증. |
| Impeccable critique · Paul Bakaus | https://github.com/pbakaus/impeccable/blob/main/skill/reference/critique.md | 같은 조회 시점. 평가 분리, 독립 에이전트와 기록 요구. |
| Impeccable audit · Paul Bakaus | https://github.com/pbakaus/impeccable/blob/main/skill/reference/audit.md | 같은 조회 시점. 기술 품질 검사 및 증거 범위. |
| UI UX Pro Max · nextlevelbuilder | https://github.com/nextlevelbuilder/ui-ux-pro-max-skill/blob/main/.claude/skills/ui-ux-pro-max/SKILL.md | API tree `e59ff376a41f7ca47b7541ad5c116495cbade3ee`. 검색 범위 축소와 디자인 시스템 생성·보존. |
| Skill authoring best practices · Anthropic | https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices | 살아 있는 공식 가이드. 간결한 본문·조건부 참조·실사용 평가와 제안의 정합성을 확인. |
