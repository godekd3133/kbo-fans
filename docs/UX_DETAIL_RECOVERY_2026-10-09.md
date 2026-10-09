# 경기 상세 오류 구분과 복구 화면

## 분석·목표

이전 웹 확인에서 reference API의 unsupported game 404가 네트워크 확인 화면으로 표시됐다. 실제 backend games producer도 게임과 schedule이 없으면 404, 일정 조회 실패는 503을 반환한다. 상세 consumer는 모든 error에서 같은 네트워크 문구를 사용했다. 원인이 확인된 경기 없음과 일시 실패를 구분하고 재시도/홈 복구를 유지한다.

## 구현·영향 범위

- Dio HTTP 404 또는 API NOT_FOUND는 경기 없음 제목과 다른 경기 선택 안내를 제공한다. 그 외 오류는 공통 describeAsyncError의 지연·연결·서버 오류 구분을 사용한다.
- null 응답은 준비/삭제 추측 없이 해당 경기 정보가 제공되지 않았다는 안내를 제공한다.
- error/missing 화면을 scroll 가능한 AppStatusCard로 통합한다. retry·home·back 및 last usable game 유지 정책은 변경하지 않는다.
- backend contract·API routing/cache/fallback·push·infra·release 변경 없음. backend games.py의 404/503 producer를 확인했다.

## 검증 기준

320x568/240%에서 HTTP404/503 각각의 표시 문구를 확인한다. retry 후 두 번째 요청에서 null 상태를 표시하고 홈 action이 실제 route 이동하는지 확인한다. 이전 버튼명 정리로 boxscore Tab과 shortcut의 text가 같아진 테스트는 TabBar descendant로 목적을 명확히 한다. 제품 action은 제거하지 않는다.

로그·화면은 `artifacts/ux-detail-recovery-2026-10-09/`에 보존한다. fixture 404 화면은 cold error UX 증거이며 실제 운영 데이터 검증이 아니다. 전체 목표는 active다.

## 검사 결과

- 전체 Flutter 649 tests passed. 최종 카드 폭 정렬 후 경기 상세 관련 테스트를 다시 실행한다. analyze 무결함.
- 웹 fixture HTTP404는 경기 없음 제목과 안전한 안내로 표시된다. 운영 API/실기기 검증으로 사용하지 않는다.

- 카드 폭 정렬 후 상세 32 tests passed·웹 build 통과. 최종 fixture404 안내/재시도 유지/홈 route 이동을 실제 웹에서 확인했다. 저장 capture 601x858, 실기기·운영 API not-run.
