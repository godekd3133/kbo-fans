# 일정 선택 날짜 유지와 매치업 안내 정리

## 분석·목표

일정 `_syncKboDate`는 현재 보고 있는 달이 이전 오늘의 달이면 자정 변경 시 선택한 날짜를 새 오늘로 덮어썼다. 같은 달의 과거/미래 경기를 확인하던 사용자의 탐색이 끊길 수 있었다. 날짜 자동 이동은 오늘을 보고 있을 때만 적용한다.

매치업 일정의 요약은 season/count 외에 가까운 순·홈/원정 무관을 반복 설명했다. 실제 경기 목록과 날짜에 드러나는 설명은 덜고 필요한 시즌과 남은 경기 수만 유지한다.

## 영향 범위·구현

- Flutter 일정 화면의 KST date sync와 매치업 summary 렌더링만 변경한다.
- 날짜가 바뀌기 전 선택일이 이전 오늘과 같은 경우만 자동 이동한다. 다른 날짜·다른 달 선택은 보존한다. 오늘 이동 버튼·달 이동·내 팀 filter는 유지한다.
- 매치업 summary는 시즌과 남은 경기 수를 독립 metadata로 표시한다. 기존 actual 정렬·홈/원정 포함 범위·filter·API/provider 요청은 유지한다.
- backend/snapshot/push/infra/release 변경 없음. backend month 계약을 사용하는 기존 scheduleProvider 유지.

## 검증 경계

자정 흐름은 kboDateProvider의 UTC instant를 KST 다음 날로 진행시켜 선택 semantics로 확인한다. source test는 실제 자정의 실기기 실행 증거가 아니다. UI 화면은 로컬 reference fixture이며 운영 일정 정확성/최신성의 증거로 삼지 않는다. 전체 목표는 진행 중이다.

## 추가 런타임 원인과 수정

웹 월 이동 중 헤더는 4월, 달력 셀은 10월, 경기 목록은 4월인 불일치를 확인했다. 초기 로딩의 Column과 완료/실패의 ListView 사이를 바꾸면서 PageView가 재부착되어 initialPage로 돌아가는 구조였다. 모든 AsyncValue 상태에서 같은 RefreshIndicator/ListView/calendar 위치를 유지하도록 통합했다. 로딩 중 notificationPredicate를 false로 두어 중복 refresh를 막는다. 지연 next-month 응답 전후 선택 semantics와 응답 후 날짜 선택을 확인하는 회귀 테스트를 추가했다. 일정 테스트 29개 통과.

- 최종 analyze 무결함·일정 29 테스트·전체 Flutter 639 테스트·웹 build 통과. 최종 웹에서 10월→6월 이동 후 header JUN 2026·6월 9일 calendar selection·6월 9일 경기 목록 일치 확인. 601x858 reference snapshot capture이며 실제 자정 실기기/운영 API 검증은 not-run.
