# 브리핑 연결 실패 처리

## 분석·목표

현재 브리핑은 원문을 여는 뉴스가 아니라 경기/순위/선수 기록으로 연결하는 앱 내부 소식이다. `_pushNewsRoute`는 유효하지 않은 route를 `/news`로 fallback하고 push했다. 같은 화면이 새로 쌓여 사용자에게는 반응이 없거나 뒤로가기를 반복해야 하는 흐름으로 보일 수 있었다.

유효하지 않은 연결은 현재 화면을 유지하며 짧게 안내한다. 정상 내부 연결과 swipe-back presentation은 유지한다. 외부 원문 열기 기능은 이번 요청에서 새로 추가하지 않는다.

## 구현·범위

- `sanitizeAppRoute(... fallback: null)`로 검증 후 invalid이면 snackbar 안내만 표시한다.
- valid target은 기존 pushAppRoute/swipeBack presentation으로 이동한다. route allowlist와 데이터 생성/캐시 정책은 변경하지 않는다.
- 빈/error 카드의 body가 없으면 빈 Text와 그 위 간격도 만들지 않는다.
- app/news consumer만 변경. backend home producer의 내부 route 계약은 유지하며 backend/infra/push/release 변경 없음.

## 검증

- 브리핑 23 tests passed, analyze 무결함.
- malformed route card tap에서 `/news` 유지, Navigator page 개수 불변, 안내 표시를 확인했다. 기존 정상 shell 이동·Cupertino swipe-back·filter reset·dedup·empty·large text 테스트도 통과했다.
- 브라우저 확인은 최종 local reference build로 수행한다. invalid route 실화면/실기기는 테스트 증거와 별도로 구분한다. 전체 목표는 진행 중이다.

- 실제 fixture에서 ‘2~5위 0.5G 혼전’을 team-name 정규식이 ‘2~’로 해석해 ‘선두 지키는 2~’로 바꾸는 오류를 확인했다. 자유 제목의 재해석 함수를 제거하고 HomeKboBriefItem의 title을 그대로 표시한다. range 제목 보존을 연결 실패 회귀 시나리오와 함께 검증했다. 최종 브리핑 23 tests passed.

- 최종 analyze 무결함·브리핑 23 tests·웹 build 통과. 웹에서 원래 순위 범위 제목 표시와 news→standings→news 복귀 확인. invalid route는 widget 회귀 증거이며 실화면/실기기 검증은 not-run. capture 601x858 reference fixture로 운영 data freshness를 주장하지 않는다.
