# 응원팀 미선택과 연결 상태 흐름 개선

## 분석과 목표

응원팀을 선택하지 않고 시작한 홈은 두 개의 팀 선택 권유, 혜택 설명, 장식 배경이 경기 정보 사이를 차지했다. 선택을 건너뛴 사용자는 우선 야구를 확인하려는 것이므로 경기 목록을 중심에 두고 선택 진입만 한 곳에 남긴다.

연결 상태 화면은 initialized/tokenReady/topics 같은 내부 값과 응답 시간이 기본 정보보다 앞섰다. 연결 결과를 먼저 보여주되 오류/진행 중/재시도는 숨기지 않고, 기술 정보는 명시적으로 펼쳐 확인하게 한다. 초기화만 완료된 상태를 기기 알림 상태 확인으로 과장하지 않는다.

## 영향 범위

| 표면 | 변경 |
|---|---|
| Flutter | No-team focus를 간결한 선택 버튼으로 전환. No-team brief/혜택/배경 제거. 연결 상태 요약과 펼치는 상세 분리 |
| backend/API | 진단의 경기 요청을 일반 홈과 같은 `/scoreboard/home` 경량 route로 변경. producer envelope와 GET/query 계약은 유지. 서버 코드 변경 없음 |
| push/Live Activity | 실제 저장·권한 요청·token registration 경로 변경 없음. readiness 요약은 initialized와 tokenReady를 모두 요구하며 web은 사용 안 함으로 구분 |
| 인프라/릴리스 | 배포·버전·서명·업로드 변경 없음 |

## 구현과 검증 기준

1. 팀을 고르지 않아도 홈의 경기 확인을 차단하지 않는다. 팀 선택 action은 한 개이고 설정/편집 동선은 유지한다.
2. No-team에 불필요한 secondary 팀 API나 반복 skeleton을 추가하지 않는다. scoreboard first frame 이후 aggregate 구독 불변을 유지한다.
3. 진단 카드는 한국어 역할명과 실제 확인 결과를 먼저 표시한다. 지원용 detail/note/latency는 펼쳐 확인하며 스크린리더에서도 접근할 수 있어야 한다.
4. push 오류와 대기 상태, 독립 재시도를 유지한다. initialized=true/tokenReady=false 상태는 등록 확인으로 표시하지 않는다.
5. source 변경 전후 actual 화면과 Flutter 검사로 확인하고, mock/fixture 화면을 실제 운영 전달의 증거로 사용하지 않는다.

## 검증 기록

- 홈/진단 집중 검사 62개 통과.
- 핵심 regression: 초기화 성공·토큰 없음의 readiness 과장 방지, 상세 정보의 기본 숨김/확장 후 표시, retry 실제 hit target, skip 사용자의 선택 진입, first scoreboard 이후 aggregate 구독.
- 원래 API path와 변경 path의 producer는 backend scoreboard route/runtime singleton에서 확인했다. `ApiGameRepository.getHomeScoreboard`와 동일한 경량 endpoint를 사용한다.
- 최종 전체 검사와 현재 빌드 캡처는 아래에 실행 결과대로 기록한다.

전체 목표는 유지한다. Native 실제 렌더, real-device notification/Live Activity와 남은 모든 흐름의 불필요한 안내는 이어서 검증한다.

기기 알림 상태의 확인 표시는 ready/초기화/tokenReady/remotePushAvailable을 함께 확인한 로컬 정보이며, 서버 등록과 실제 전달 성공을 보장하는 결과가 아니다.

## 최종 실행 결과

- Flutter 전체 633 tests passed, analysis No issues found, 웹 release/API mode build 성공.
- No-team 홈의 한 개 선택 진입과 경기 목록 우선 배치를 actual browser에서 확인했다. 저장 전후 캡처는 폭이 달라 pixel-perfect 비교 근거로 사용하지 않는다.
- 연결 상태는 실제 기본 요약과 상세 확장 동작을 확인했다. ExpansionTile의 고정 SDK 지원 옵션으로 button semantics를 추가했고 regression에서도 버튼 역할을 검증했다.
- PushService의 debugState는 초기화 정보이며 실제 server registration/delivery가 아님을 확인했다. 따라서 표시명은 기기 알림 상태, 긍정 상태는 기기 정보 확인으로 구분하고 ready/초기화/token/remote availability를 함께 확인한다. status=failed 또는 token 없음은 확인되지 않은 상태로 유지한다.
- `artifacts/ux-first-use-2026-10-09/verification.json`, `review.html`, 캡처 및 지속 로그를 보존했다.
- 네이티브 실제 화면/실기기 전달/남은 flow review는 전체 목표에서 여전히 미완료다.
