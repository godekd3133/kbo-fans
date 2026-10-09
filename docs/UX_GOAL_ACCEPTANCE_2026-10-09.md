# 전체 UX 고도화 목표의 검증 현황

사용자 목표는 첫 실행부터 모든 흐름이 편리·유용·신뢰 가능하고 완성도 높게 느껴지며, 반복 안내와 기계적인 표현·점 구분 문구를 줄이는 것이다. 아래는 전체 완료 여부를 판단하는 범위다. 각 루프의 통과를 전체 완료로 간주하지 않는다.

| 흐름 | 구현·현재 증거 | 남은 확인 |
|---|---|---|
| 첫 실행·응원팀 선택/건너뛰기 | 고정 하단 action, skip 저장 분리, 웹 화면·테스트 | iOS/Android 설치 후 첫 실행·권한 거절/허용 |
| 홈 경기 확인·내 팀 | scoreboard first-frame 유지, no-team 중복 안내 제거, score ordering·큰 글자 테스트·웹 | 실제 운영 API 현재 경기/실기기 poll·앱 재진입 |
| 경기 상세 | 이닝·중계·boxscore·lineup 정보 정리, rank/score identity·retry 테스트 | 최신 변경의 빈 상태·실기기 tab 이동·복귀 |
| 일정 | 빈 날 다음 경기·달 이동, loading PageView 유지, KST 선택 보존 테스트·웹 | 매치업 전체 시즌 웹 fixture 완전성·실제 자정 |
| 순위·기록 | 중복 요약 제거, season 왕복·큰 글자·비교·부분 빈 기록 테스트·웹 | 상세 leaderboard 응답·운영 과거 데이터 identity |
| 브리핑 | 기본 노출 3+3, 더보기/필터 초기화·출처 sheet, 웹·테스트 | 잘못된 내부 연결 실화면·실기기 복귀 |
| 알림함·설정 | unread count·retention·readiness 요약과 기술정보 분리, 웹·테스트 | 기기 권한 변경·알림 실제 수신/탭 이동 |
| 위젯·Live Activity | 구분 문자 제거, native target compile 성공 | 실제 native 크기·잠금화면/Island render·백엔드 전달 |
| 스타일·카피 | 반복 문장 제거, metadata Wrap·날짜/소수점 유지 테스트, 여러 웹 화면 | 모든 큰 글자/선택색/밝은 모드 전수 실화면 |

## 증거 기준

- 소스/Flutter 테스트와 backend 테스트는 각각 독립적으로 보고한다.
- 로컬 reference fixture의 표시는 운영 API freshness·실제 과거 정확성·푸시 전달을 증명하지 않는다.
- 현재 capture가 601px이면 390px 실화면 검증으로 표시하지 않는다. 테스트에서 320/390px layout 검증과 실제 capture는 별개다.
- Native compile 성공은 WidgetKit/Android 실제 render 증거가 아니다.
- 전체 목표는 active. 남은 runtime 확인을 건너뛰고 완료로 표시하지 않는다. 추가 수정은 관측된 문제와 원인에 근거해 진행한다.

경기 상세 recovery 추가: HTTP404와503 구분, 320x568/240% action 접근·retry 후 null·홈 복구 회귀를 확인했다. 전체 Flutter 649 테스트 통과. 웹 fixture 404의 상태 표시도 확인했으며 운영/실기기 경계는 유지한다.

브리핑 연결·제목 추가: invalid route가 page stack을 늘리지 않는 회귀와 range 제목 보존을 확인했다. 정상 news→standings→news는 웹에서도 확인했다. current 브리핑은 내부 기록 연결이며 외부 원문 기능을 임의로 추가하지 않는다.

알림 설정 추가: local write false·partial·readback failure의 표시/복구와 실패 카드 lifecycle을 확인했다. 실제 OS 저장 실패·server sync·푸시 전달은 별도 runtime 증거가 필요하다.

iOS Debug 전체 앱 no-codesign compile 성공. physical device는 eligible이나 사용자 사용 중으로 설치/실행 not-run. 운영 2025 saves API 응답의 identity/rank1/30 rows와 reference avg leaderboard 웹 표시는 확인했다. 모든 leaderboard/실기기 동작 완료를 뜻하지 않는다.

390px 증거 추가: inbox의 DOM logical390·scale1과 PNG390x844를 확인했다. 다른 화면의 이전 601px 증거를 390px로 소급하지 않는다. empty→settings 실제 진입을 확인했다. settings web에서는 알림 service가 kIsWeb로 비활성인데 권한 요청 action이 노출됨을 관측했고 후속 검토 대상으로 남긴다.

웹 settings 지원 불일치 해결: shared service capability와 같은 build flags에서 unsupported 조작을 제거했고 PNG390x844로 실제 표시를 확인했다. 전체 Flutter656 tests 통과. native OS 권한·등록·전달 증거는 여전히 별도다.
