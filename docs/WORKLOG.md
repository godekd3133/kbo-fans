# 작업 이력 (Work Log)

---

## 2026-05-19: v4 UX 보완안 실제 UI 반영

### 완료
- [x] 설정 화면 용어를 `바로 알림 / 묶음 요약 / 따라가기만 / 끄기`로 정리하고 중복 제목을 `알림` / `장면별 알림` 구조로 조정
- [x] 홈 대표 경기 카드의 CTA를 예정/라이브/종료 상태별로 분리하고, `중계 보기`와 알림/따라가기 액션이 같은 callback을 쓰지 않도록 수정
- [x] 종료 경기 상세에서 하이라이트가 탭 진입을 가리지 않도록 스코어 탭 footer로 이동
- [x] 마이팀 브리프의 최근 3경기 chip을 가로 스크롤로 바꾸고 CTA/metric 밀도와 하단 safe area를 보강
- [x] 홈/경기상세의 stale성 문구를 `방금 업데이트` 고정에서 상태별 `최종 기록`, `예정` 등으로 분기
- [x] `docs/APP_SPEC.md`, `CHANGELOG.md`에 변경된 UX 흐름과 용어 반영

### 검증
- [x] `cd app && fvm dart format lib/features/settings/settings_screen.dart lib/features/home/widgets/my_team_game_card.dart lib/features/home/home_screen.dart lib/features/game_detail/game_detail_screen.dart lib/features/game_detail/tabs/score_tab.dart`
- [x] `cd app && fvm flutter analyze`
- [x] `cd app && fvm flutter test test/widget_test.dart test/services/push_notification_service_test.dart`
- [x] `cd app && fvm flutter build web --release --dart-define=APP_ENV=local`
- [x] `node artifacts/kbo-v4-ux-eval/capture-v4-screens.js`
- [x] 화면 산출물 갱신: `artifacts/kbo-v4-ux-eval/03-home-state.png`, `01-settings-playbook.png`, `04-settings-surfaces.png`, `05-settings-delivery-picker.png`, `02-game-detail-relay.png`

### 메모
- native Live Activity / Android 홈 위젯 실기기 캡처는 아직 별도 QA로 남는다.
- 현재 web smoke 기준 홈 CTA 잘림, 설정 용어 혼란, 경기 상세 하이라이트 우선 노출 문제는 해소됐다.

---

## 2026-05-19: 일정 구장별 보기 퀵링크 추가

### 완료
- [x] 구장별 일정 상단에 구장명과 경기 수를 보여주는 가로 퀵링크 버튼 row 추가
- [x] 퀵링크 탭 시 해당 구장 섹션 헤더로 부드럽게 스크롤되도록 `Scrollable.ensureVisible` 연결
- [x] 월별 `PageView`, 팀 필터, 구장별 팀 필터 구조는 유지하면서 월+구장 단위 section key를 사용해 월 스와이프와 충돌하지 않도록 조정
- [x] `docs/APP_SPEC.md`, `docs/FIGMA_PROMPT.md`, `CHANGELOG.md`에 사용자 체감 동작 반영

### 검증
- [x] `cd app && fvm flutter analyze lib/features/schedule/schedule_screen.dart`
- [x] `cd app && fvm flutter analyze`
- [x] `cd app && fvm flutter build web --release`

### 메모
- 기존 구장별 보기에는 구장 섹션이 아래로 길게 나열되어 원하는 구장으로 이동하려면 수동 스크롤이 필요했다.
- 퀵링크는 현재 필터 결과에 남은 구장만 표시하므로 마이팀/팀별 필터와 같은 목록 기준을 공유한다.

---

## 2026-05-19: v4 Moment Surface UX 화면 평가

### 완료
- [x] v4 Moment Subscription / Surface Strategy 기준으로 실제 Flutter web 390x844 화면을 재캡처
- [x] 홈, 설정 알림 플레이북, 앱 밖 표면 설명, 전달 방식 picker, 경기 상세 화면을 화면 근거와 함께 평가
- [x] Apple HIG, Android Live Updates/Notification Permission, WCAG Target Size, NN/g notification/status feedback 기준으로 UX 원칙 정리
- [x] `docs/UX_REVIEW_V4_MOMENT_SURFACE_2026-05-19.md`에 P1/P2/P3 개선 우선순위 문서화
- [x] `docs/UX_FIX_PROPOSAL_V4_MOMENT_SURFACE_2026-05-19.md`에 문제별 원인, 수정안, 구현 범위, QA/DoD를 추가 문서화

### 검증
- [x] `GET http://127.0.0.1:8000/api/health`
- [x] `node artifacts/kbo-v4-ux-eval/capture-v4-screens.js`
- [x] 화면 산출물: `artifacts/kbo-v4-ux-eval/03-home-state.png`, `01-settings-playbook.png`, `04-settings-surfaces.png`, `05-settings-delivery-picker.png`, `02-game-detail-relay.png`
- [x] 코드 위치 확인: `home_screen.dart`, `my_team_game_card.dart`, `settings_screen.dart`, `game_detail_screen.dart`, native widget/live activity files

### 메모
- 현재 UX 평가는 82/100으로 판단했다. 방향은 맞지만 홈 CTA 노출, `중계 보기` 진입 결과, Live/Widget/stale 용어 명확성은 후속 수정이 필요하다.
- 수정 순서는 copy 정리, 홈 CTA 상태 분기, 카드 callback 분리, 상세 relay 우선 노출, 브리프 compact 조정, native surface QA 순서가 가장 리스크가 낮다.

---

## 2026-05-19: 기록실 runtime 검증 및 OPS+ snapshot 정규화

### 완료
- [x] 기록실 overview, 리더보드, 팀 기록 합본, 선수 상세 API를 실제 local FastAPI 경로로 재검증
- [x] 10개 구단 `/api/team/{teamId}/records?season=2026` 합본 응답이 모두 `200`으로 종료되고 선수 목록/타격/투수 스탯을 포함하는지 확인
- [x] 구형 `records_overview` snapshot에 `opsPlus`가 없어도 backend 응답 단계에서 현재 계약에 맞춰 OPS+ 리더보드를 계산하도록 보정
- [x] 하단 탭 실제 클릭으로 기록실 첫 화면과 리더보드 상세 진입을 390x844 web smoke로 확인

### 검증
- [x] `backend/.venv/bin/python -m compileall backend/src backend/tests/test_records_overview.py backend/tests/test_snapshot_services.py`
- [x] `backend/.venv/bin/pytest -q backend/tests/test_records_overview.py backend/tests/test_snapshot_services.py backend/tests/test_teams.py`
- [x] 실제 API 계측: `records/overview` 리더보드 `avg/hr/ops/opsPlus/era` 각 5건 포함
- [x] 실제 API 계측: `leaderboard avg/hr/ops/opsPlus/era`는 24~30건, unsupported `war`는 빈 목록으로 종료
- [x] 실제 API 계측: `KT/SS/LG/HT/SK/WO/LT/HH/NC/OB` 팀 기록 합본이 모두 선수 60명 이상과 팀 타격/투수 스탯을 반환
- [x] 웹 smoke 산출물: `artifacts/kbo-records-check/records-tab-overview-v2.png`, `artifacts/kbo-records-check/records-team-after-click-v2.png`

### 메모
- 기록실 직접 URL(`/records`, `/records/team/*`, `/records/leaderboard/*`)은 web boot 단계에서 `/home`으로 되돌거나 `Page Not Found`가 나는 deep-link 문제가 별도로 관찰됐다. 하단 탭/앱 내 네비게이션은 동작하지만, web preview/release 딥링크 안정화는 후속 과제로 분리한다.

---

## 2026-05-19: v4 Moment Subscription 실제 앱 반영

### 완료
- [x] `docs/design/kbo-fans-mobile-ui-alerts-outside-v4-2026-05-19/preview.png` 기준의 Moment Subscription / Surface Strategy를 실제 Flutter 화면에 맞춤
- [x] 앱 전역 색상/카드/입력/버튼 테마를 v4 보드의 `#07090C`, `#10141A`, `#171D24`, `#323A45`, `#2979FF`, `#FF4444` 체계로 정리
- [x] 설정 화면을 `알림 플레이북` 중심으로 정리하고 Moment별 `바로 / 요약 / Live만 / 끄기` 전달 방식을 v4 카드 톤으로 표시
- [x] 경기 상세 라이브 화면의 `경기 따라가기`를 Live 표면 / Push / Widget 역할 분리형 CTA로 보강
- [x] 홈, 일정, 기록실, 온보딩의 모바일 폭, 카드 반경, 헤더 구조, 하단 탭 밀도를 v4 보드의 compact dark sports tone에 맞춰 유지
- [x] 하단 탭을 `홈 / 일정 / 순위 / 기록실 / 설정` 순서와 작은 outline icon 상태로 정리

### 검증
- [x] `cd app && fvm flutter analyze`
- [x] `cd app && fvm flutter test test/services/push_notification_service_test.dart test/widget_test.dart`
- [x] local FastAPI + web static preview 390x844 캡처 확인: 홈, 일정, 기록실, 설정, 경기 상세

### 메모
- 이전 빌드/브라우저 캐시에서는 문서 시안만 있고 Flutter UI가 일부만 반영된 상태로 보일 수 있어, web service worker/cache를 지우고 새 번들로 확인해야 한다.
- v4 기준은 알림 강도 다이얼이 아니라 야구 장면 Moment와 전달 표면 분리다. Push는 즉시 이벤트, Live 표면은 따라가는 경기 상태, Widget은 개인화 상태판 역할로 제한한다.

---

## 2026-05-19: Compact scoreboard / 앱 밖 refresh 루프 축소

### 완료
- [x] 백엔드 `/scoreboard/compact` endpoint 추가
- [x] compact endpoint가 위젯/Live 표면용으로 최대 1경기만 선택하고, 해당 경기만 enrich하도록 구현
- [x] 최초 실행 remote prefetch가 홈 진입을 막지 않도록 blocking startup prefetch 비활성화
- [x] 위젯 background refresh가 일반 API 모드에서 `/scoreboard/compact`를 우선 사용하도록 변경
- [x] 위젯 sync에서 relay/current-at-bat 조회를 제거해 위젯 갱신이 별도 문자중계 크롤링 루프가 되지 않도록 정리
- [x] Live Activity sync 내부의 direct KBO current-at-bat fallback 제거
- [x] KBO live scoreboard detail payload의 총점이 비어 있을 때 이닝별 점수 합산으로 `score`를 보정
- [x] 단건 경기 상세가 오늘/미래 경기의 오래된 `games/{gameId}` snapshot을 먼저 반환하지 않도록 수정
- [x] 경기 종료 전환 직후 KBO scroll scoreboard가 비어도 `LiveTextView1` 이닝표와 main score로 상세 스코어를 보정
- [x] 앱 상세 캐시 키를 `game_detail_v2:{gameId}`로 올려 기존 0:0 상세 캐시를 재사용하지 않도록 조정
- [x] v4 delivery 모델에 맞춰 immediate Moment만 direct push topic을 만들도록 테스트 기대값 갱신
- [x] `docs/APP_SPEC.md`, `docs/KBO_DATA_REFRESH_ARCHITECTURE_2026-05-19.md`에 compact endpoint와 남은 Live state 과제 반영

### 검증
- [x] `backend/.venv/bin/python -m compileall backend/src`
- [x] `backend/.venv/bin/pytest -q backend/tests/test_scoreboard_service_cache.py backend/tests/test_games.py backend/tests/test_snapshot_services.py`
- [x] `backend/.venv/bin/pytest -q`
- [x] 실제 KBO upstream을 타는 service 계측: 2026-05-19 기준 home cold는 detail/view1 각 5회, compact cold는 각 1회로 감소 확인
- [x] 실제 KBO live 경기 기준 service 계측: LG-KIA `20260519LGHT0` 응답이 390ms 수준으로 종료되고, 점수 `LG 0 : 12 KIA` 계산 확인
- [x] 실제 KBO 종료 전환 경기 기준 service/API/web 상세 계측: KT-삼성 `20260519KTSS0`이 `FINAL`, `KT 2 : 10 삼성`, 이닝표/H/E/B 포함으로 렌더됨 (`artifacts/kbo-live-loading-check/detail-ktss-final-transition-fixed.png`)
- [x] 로컬 web release + FastAPI + system Chrome headless 390x844 smoke: 첫 실행 seed 상태에서 blocking loader가 사라지고 홈 live 카드가 렌더됨 (`artifacts/kbo-live-loading-check/home-lg-nonblocking-fixed-score.png`)
- [x] `cd app && fvm dart format --set-exit-if-changed lib/data/repositories/api_game_repository.dart lib/services/widget_sync_service.dart lib/services/live_activity_service.dart lib/features/settings/settings_screen.dart test/services/push_notification_service_test.dart`
- [x] `cd app && fvm flutter analyze`
- [x] `cd app && fvm flutter test test/widget_test.dart test/data/models/records_overview_test.dart test/services/push_notification_service_test.dart`

### 메모
- Live Activity의 batter/pitcher/B-S-O 표시는 client direct crawl로 채우지 않고, 추후 backend-owned compact live state payload로 복구하는 쪽이 맞다.
- `settings_screen.dart`의 `SizedBox(minHeight:)`는 현재 Flutter API에 없는 파라미터라 전체 analyze를 막고 있어 `ConstrainedBox`로 같은 의도를 유지해 수정했다.

---

## 2026-05-19: 알림 플레이북 / 앱 밖 경험 v4 앱 반영

### 완료
- [x] 설정 화면의 단순 알림 토글을 Moment별 `바로 / 요약 / Live만 / 끄기` 전달 방식 선택 UI로 전환
- [x] 기본 플레이북을 `경기 시작/경기 종료/라인업=요약`, `득점/홈런/역전=바로`, `이닝 교대=Live만`으로 정리
- [x] 앱 시작 시 OS 알림 권한을 바로 요청하지 않고, `권한 확인`, `바로 알림`, `경기 따라가기` 같은 명시적 사용자 action 이후에만 요청하도록 변경
- [x] 로컬 경기 이벤트 알림과 FCM topic 구독이 `바로 알림` Moment만 대상으로 삼도록 조정
- [x] 경기 상세 라이브 경기 헤더 아래에 `경기 따라가기` CTA를 추가하고, Live Activity는 사용자가 선택한 경기만 동기화하도록 변경
- [x] `docs/APP_SPEC.md`, `docs/FIGMA_PROMPT.md`, `CHANGELOG.md`를 실제 구현된 Moment 목록과 기본값에 맞춰 동기화

### 검증
- [x] `cd app && fvm dart format lib/services/push_notification_service.dart lib/services/game_event_alert_service.dart lib/services/live_activity_service.dart lib/features/game_detail/game_detail_screen.dart lib/features/settings/settings_screen.dart test/services/push_notification_service_test.dart`
- [x] `cd app && fvm flutter analyze lib/services/push_notification_service.dart lib/services/game_event_alert_service.dart lib/services/live_activity_service.dart lib/features/game_detail/game_detail_screen.dart lib/features/settings/settings_screen.dart test/services/push_notification_service_test.dart`
- [x] `cd app && fvm flutter test test/services/push_notification_service_test.dart test/widget_test.dart`

---

## 2026-05-19: 실시간/스냅샷 데이터 분리 및 중복 로딩 기술 검토

### 완료
- [x] `docs/KBO_DATA_REFRESH_ARCHITECTURE_2026-05-19.md`에 live / warm cache / persisted snapshot / bundled bootstrap 데이터 분류 기준 문서화
- [x] 백엔드 service/crawler/cache/snapshot 책임 경계와 endpoint별 freshness matrix 정리
- [x] 반복 크롤링 방지를 위한 singleflight, rate-limit, stale-while-revalidate, request budget 설계안 정리
- [x] 홈, 일정, 경기 상세, Score/Relay/Boxscore/Lineup 탭, 기록실 화면의 현재 over-fetch 후보와 목표 호출 구조 검토
- [x] 실제 파일/라인 기준 evidence map 추가
- [x] widget background, local alert, direct KBO repository, backend route fan-out까지 추가 검토
- [x] P0/P1/P2 구현 순서와 구현 후 request count 목표치 정리

### 원인
- 실시간 데이터와 과거/기록성 데이터를 한 정책으로 처리하면, live freshness를 잃거나 반대로 안정 데이터까지 매번 KBO 웹을 다시 긁게 된다.
- 일부 화면은 실제로 필요한 payload보다 넓은 provider를 구독하거나 preload를 통해 detail/relay/boxscore/lineup/player data를 한꺼번에 데우고 있어 로딩 중첩과 upstream 부담이 생길 수 있다.
- 화면 외에도 widget background refresh와 local alert processing이 별도 실시간 refresh surface가 될 수 있어, 화면 provider만 줄여서는 전체 KBO 호출량을 통제할 수 없다.

### 검증
- [x] 관련 코드 경로 확인: `app/lib/data/providers.dart`, `app/lib/features/home/home_screen.dart`, `app/lib/features/schedule/schedule_screen.dart`, `app/lib/features/game_detail/*`, `app/lib/services/game_detail_preload_service.dart`, `backend/src/kbo_fans_backend/services/*`
- [x] 추가 코드 경로 확인: `app/lib/services/widget_sync_service.dart`, `app/lib/services/game_event_alert_service.dart`, `app/lib/data/repositories/kbo_direct_repository.dart`, `backend/src/kbo_fans_backend/api/routes/*`
- [x] 문서 변경 범위 확인: `docs/KBO_DATA_REFRESH_ARCHITECTURE_2026-05-19.md`

---

## 2026-05-18: KBO 원천 웹 의존도 완화 1차 보강

### 완료
- [x] `docs/KBO_DATA_RESILIENCE_PLAN_2026-05-18.md`에 live / warm cache / persisted snapshot / bundled bootstrap 기준 정리
- [x] 월간 일정 API가 성공한 비어 있지 않은 payload를 항상 schedule snapshot으로 남기도록 조정
- [x] 기록실 leaderboard API가 `leaderboard/{season}:{metric}` snapshot을 저장/조회하도록 보강
- [x] 앱 leaderboard API 실패 시 bundled records overview snapshot에서 metric별 리더보드를 복구하도록 fallback 추가

### 원인
- KBO 공식 웹/HTML/ASMX 응답은 느리거나 마크업이 바뀌기 쉬운데, 일부 경로가 요청 시점 recrawl 또는 direct KBO fallback에 의존했다.
- 일정 snapshot 저장 조건이 모든 경기가 종료된 월로 제한되어, 현재 월 KBO 일정 원천이 깨졌을 때 재사용할 마지막 정상 월 payload가 부족할 수 있었다.
- records overview는 snapshot-first였지만 leaderboard 단건 endpoint는 snapshot 저장/조회가 없어 같은 기록 데이터를 다시 원천 호출할 여지가 있었다.

### 검증
- [x] `cd backend && uv run --with pytest pytest tests/test_schedule.py tests/test_records_overview.py tests/test_snapshot_services.py -q`
- [x] `cd backend && python3 -m compileall src tests/test_schedule.py tests/test_records_overview.py`
- [x] `cd app && fvm flutter analyze lib/data/repositories/api_player_repository.dart`

---

## 2026-04-25: 박스스코어 주자 상태 `-` 표시 보정

### 완료
- [x] direct KBO relay parser가 베이스 이미지에서 `ground_base*.png`를 못 읽고 `alt="주자"`만 받은 경우, 1/2/3루 주자 이름으로 주자 상태를 재구성하도록 보강
- [x] 박스스코어 라이브 요약의 `주자` 타일이 `baseState`가 비어 있어도 주자 이름 필드로 `주자1루`, `주자1,3루`, `만루` 등을 표시하도록 보정
- [x] 문자중계 현재 타석 배지도 같은 fallback을 사용하도록 맞춰 표시 일관성 개선
- [x] 백엔드 relay crawler도 동일하게 주자 이름 기반 baseState fallback을 추가

### 원인
- KBO live text HTML에서 주자 이미지가 `ground_base*.png` 형태로 오면 정상 표시됐지만, 일부 응답에서는 `alt="주자"`만 남아 parser가 빈 문자열로 처리했다
- 박스스코어 탭은 빈 `baseState`를 `-`로 표시했기 때문에 실제 주자가 있어도 `-`로 보일 수 있었다

### 검증
- [x] `cd app && fvm flutter analyze lib/data/repositories/kbo_direct_repository.dart lib/features/game_detail/tabs/boxscore_tab.dart lib/features/game_detail/tabs/relay_tab.dart`
- [x] `cd app && fvm flutter test test/widget_test.dart`
- [x] `cd backend && uv run --with pytest pytest tests/test_relay_crawler.py -q`
- [x] `cd backend && python3 -m compileall src tests/test_relay_crawler.py`

---

## 2026-04-25: 라인업 선발투수 프로필 이미지 보강

### 완료
- [x] 라인업 데이터 모델에 선발투수 id/imageUrl 후보를 추가
- [x] 앱 direct KBO 라인업 생성 시 `Main.asmx/GetKboGameList`의 `T_PIT_P_ID` / `B_PIT_P_ID`로 선발투수 이미지 URL을 즉시 구성하도록 보강
- [x] 백엔드 라인업 API도 main game 메타데이터에서 선발투수 id/name/imageUrl을 함께 내려주도록 보강
- [x] 라인업 탭 이미지 매칭을 선수목록 `imageUrl`뿐 아니라 선수 id 기반 CDN URL, 현재 타석 relay 이미지, 괄호/표기 변형 제거 매칭까지 사용하도록 개선
- [x] 상세 선로딩 서비스가 선발투수 id/imageUrl 기반 이미지를 미리 캐시하도록 보강

### 원인
- 선발 카드가 이름 기반 선수 이미지 맵에 의존해, 선수목록 로딩 지연/실패 또는 이름 표기 변형이 있으면 즉시 fallback 글자 카드로 떨어질 수 있었음
- 실제 KBO main game payload에는 선발투수 id가 이미 있으므로, 선수목록 조회와 무관하게 `person/middle/{season}/{playerId}.jpg` URL을 만들 수 있었음

### 검증
- [x] `cd app && fvm flutter analyze lib/data/models/boxscore.dart lib/data/repositories/api_game_repository.dart lib/data/repositories/kbo_direct_repository.dart lib/features/game_detail/tabs/lineup_tab.dart lib/services/game_detail_preload_service.dart`
- [x] `cd app && fvm flutter test test/widget_test.dart`
- [x] `cd backend && uv run --with pytest pytest tests/test_lineup.py tests/test_schedule.py -q`
- [x] `cd backend && python3 -m compileall src tests/test_lineup.py`

---

## 2026-04-25: 문자중계 로딩 대기 고착 방지

### 완료
- [x] direct KBO 문자중계가 경기 전체 스코어보드 조회를 먼저 기다리지 않고 `Main.asmx` 메타데이터와 live text 요청으로 바로 진입하도록 조정
- [x] `LiveText.aspx` / `LiveTextView2.aspx` 문자중계 요청은 startup/history warm 의 전역 KBO 요청 queue 를 우회하도록 조정
- [x] 세션 준비용 `LiveText.aspx` GET 은 2초 안에 끝나지 않으면 건너뛰고 실제 중계 데이터인 `LiveTextView2.aspx` POST 로 진행하도록 조정
- [x] 문자중계 요청에 dedupe, timeout, 시작/완료 로그를 추가해 로딩 고착과 원인 추적성을 개선
- [x] 경기 상세 자동 새로고침이 진행 중일 때 같은 provider 를 반복 invalidate 하지 않도록 guard 추가
- [x] 라이브 경기 상세 자동 갱신 주기를 30초로 조정하고 종료/취소/서스펜디드 경기는 반복 갱신을 중단
- [x] direct 선수 목록 조회가 선수별 상세/누적기록 페이지를 대량 병렬 호출하지 않도록 정리하고, 선수 상세 화면에서만 상세 데이터를 조회하도록 조정

### 원인
- `getRelayData()`가 먼저 `getGame()`을 호출하면서 당일 전체 스코어보드와 각 경기 `GetScoreBoardScroll` 조회를 기다렸고, startup/history warm 요청이 동시에 쌓이면 문자중계가 사용자 탭 진입 뒤에도 뒤로 밀릴 수 있었음
- 상세 화면 타이머가 10~15초마다 relay provider 를 다시 invalidate 해, 느린 요청이 끝나기 전에 로딩 상태가 반복 갱신될 수 있었음
- 팀 선수 목록 direct fallback 이 선수마다 상세/누적기록 페이지를 동시에 요청해 KBO 원본 연결을 포화시키고, 문자중계 요청까지 timeout 가능성을 높였음

### 검증
- [x] `cd app && fvm flutter analyze lib/data/repositories/kbo_direct_repository.dart lib/data/repositories/kbo_direct_player_repository.dart lib/features/game_detail/game_detail_screen.dart`

---

## 2026-04-25: 경기 상세 데이터/이미지 선로딩

### 완료
- [x] 홈 스코어보드에서 마이팀/라이브/종료 경기 우선으로 최대 3경기의 상세 데이터를 백그라운드 선로딩하도록 추가
- [x] 일정 화면에서 선택 날짜의 상위 경기와 탭 직전 경기 상세 데이터를 선로딩하도록 추가
- [x] 경기 상세 진입 직후 문자중계/박스스코어/라인업 데이터를 미리 읽고, 라인업·문자중계·박스스코어에 등장하는 선수 프로필 이미지를 캐시에 올리도록 추가
- [x] 선로딩은 3분 TTL과 in-flight dedupe 를 적용해 같은 경기를 반복 요청하지 않도록 제한
- [x] 예정 경기는 팀 로고/기본 정보 중심으로 두고, 문자중계·박스스코어·라인업 선로딩은 라이브/종료 경기 위주로 제한

### 원인
- 문자중계/박스스코어 탭은 데이터 provider 가 준비되어도 선수 이미지는 실제 위젯 렌더 시점에 내려받아 첫 진입 체감이 늦을 수 있었음
- 홈/일정에서 이미 어떤 경기를 볼 가능성이 높은지 알 수 있으므로, 상세 진입 전에 핵심 payload 와 이미지 캐시를 미리 데우는 편이 체감 지연을 줄일 수 있음

### 검증
- [x] `cd app && fvm flutter analyze lib/services/game_detail_preload_service.dart lib/features/home/home_screen.dart lib/features/schedule/schedule_screen.dart lib/features/game_detail/game_detail_screen.dart`

---

## 2026-04-25: 일정 탭 당일 경기 상태 보정

### 완료
- [x] 앱 direct KBO 일정 월 조회 결과에 오늘 날짜 `Main.asmx/GetKboGameList` 메타데이터를 합쳐 진행 중 경기가 `경기 전`으로 보이지 않도록 수정
- [x] 백엔드 일정 API도 오늘 날짜 일정에 main game 상태/점수/구장 메타를 병합하도록 보강
- [x] synthetic gameId 가 main game id 와 정확히 일치하지 않는 경우에도 원정/홈 팀 ID 기준으로 main game 을 매칭하도록 보완

### 원인
- `GetScheduleList` 기반 일정 월 데이터는 진행 중에도 action/status 값이 `SCHEDULED` 상태로 남을 수 있었고, 기존 보강 로직은 종료 경기 점수 누락만 처리했다
- 실제 진행 상태는 `Main.asmx/GetKboGameList`의 `GAME_STATE_SC=2`에 있으므로 일정 탭도 이 메타데이터를 합쳐야 했다

### 검증
- [x] `cd app && fvm flutter analyze lib/data/repositories/kbo_direct_repository.dart lib/features/schedule/schedule_screen.dart lib/features/schedule/widgets/schedule_game_card.dart`
- [x] `cd backend && uv run --with pytest pytest tests/test_schedule.py -q`
- [x] `cd backend && python3 -m compileall src tests/test_schedule.py`

---

## 2026-04-02: 문자중계 선수 프로필/볼카운트 시각화 강화

### 완료
- [x] 경기 상세 `문자중계`의 현재 타석 카드에 B/S/O를 숫자+색상 요약 카드로 재구성
- [x] 현재 타석의 타자/투수 프로필 이미지 우선순위를 정리해 direct relay 이미지와 선수 이미지 맵 fallback을 함께 사용
- [x] 문자중계 주요 플레이 카드에 주체 선수 아바타를 추가
- [x] 문자중계 타석 카드를 방송형 레이아웃으로 재구성해 회차 헤더, 상대투수/상대팀, 선수 프로필, 플레이 결과, 순번형 투구 로그가 한 카드 안에 보이도록 조정
- [x] 투구 로그를 `N구` 기준으로 다시 보여주고, 볼/스트라이크/파울 결과 배지와 누적 B/S 카운트 요약을 같이 노출
- [x] 문자중계 이닝 칩을 `전체 / N회초 / N회말` 선택형 필터로 바꿔 회차별 중계만 따로 볼 수 있게 조정
- [x] 박스스코어의 `핵심 타자` / `핵심 투수` 카드에 선수 프로필 이미지와 고대비 텍스트 스타일을 적용
- [x] iOS 잠금화면 Live Activity에서 스코어 컬럼이 화면 양끝으로 벌어지지 않도록 중앙 정렬 그룹으로 조정
- [x] iOS 잠금화면 Live Activity와 iOS 위젯 점수 영역에 팀 로고가 보이도록 팀 ID 동기화와 SwiftUI 로고 렌더 추가
- [x] iOS 잠금화면 Live Activity와 iOS 위젯에 현재 타석 타자/투수와 투구 수(`N구`)가 함께 보이도록 payload와 표시 라인 확장
- [x] 홈 `지금 보면 좋은 정보`의 선수 카드 탭 시 최근 기록 요약 바텀시트를 먼저 보여주고 선수 상세로 이어지게 조정
- [x] `docs/APP_SPEC.md`, `CHANGELOG.md`에 문자중계 UI 변경사항 반영

### 원인
- 기존 문자중계 탭은 현재 타석 카드에 선수 정보가 일부 있었지만, 개별 중계 이벤트에서는 누구 플레이인지 시각적으로 즉시 연결되기 어려웠음
- 투구 로그는 텍스트만 보여서 `1구 스트라이크`, `2구 파울` 이후 현재 카운트가 어떻게 누적됐는지 한 번에 읽기 어려웠음

### 검증
- [x] `cd app && fvm flutter analyze lib/features/game_detail/tabs/relay_tab.dart`

### 비고
- 투구 로그의 누적 카운트는 pitch text(`N구`, `볼`, `스트라이크`, `파울`)를 기준으로 UI에서 계산해 표시한다
- pitch 로그별 아웃 수는 원문 데이터가 충분하지 않아 이번 단계에서는 현재 타석 카드의 B/S/O 강조를 우선 유지했다

---

## 2026-04-02: 푸시 토픽 동기화 오작동 방지

### 완료
- [x] 마이팀 미선택 상태에서는 마이팀 이벤트 푸시 토픽을 구독하지 않도록 조정
- [x] FCM 토큰 갱신 시 초기 캡처값이 아니라 현재 저장된 마이팀 기준으로 재동기화하도록 수정

### 원인
- 기존 구현은 `myTeam == null` 인 상태에서 `*_ALL` 토픽 이름을 만들어 사실상 리그 전체 이벤트를 받게 될 수 있었음
- 토큰 refresh 리스너가 `initialize()` 시점의 `myTeam` 값을 캡처해, 이후 응원팀 변경 뒤 토큰이 바뀌면 예전 팀 기준으로 재구독할 여지가 있었음

### 검증
- 코드 경로 기준으로 `setTeam()` 이후 `syncRegistration()` 이 저장된 `myTeam` 과 동일한 값을 사용하도록 확인
- 토큰 refresh 경로가 `syncRegistration(forceToken: ...)` 를 통해 최신 저장 팀을 다시 읽도록 확인

---

## 2026-04-02: 종료 경기 예매 정보 숨김

### 완료
- [x] 경기 상세에서 종료/취소/서스펜디드 경기는 예매 정보 카드를 숨기도록 조정
- [x] 일정 카드에서 종료/취소/서스펜디드 경기는 예매 요약을 숨기도록 조정
- [x] 백엔드 `ticketInfo` 생성 로직이 종료 상태에서는 값을 내려주지 않도록 정리
- [x] 종료 경기 예매 비노출 정책을 문서와 테스트에 반영

### 검증
- Flutter 위젯 테스트에 종료 경기 예매 비노출 케이스 추가
- 백엔드 테스트에 `FINAL` 상태 `ticketInfo is None` 케이스 추가

### 비고
- 기존 캐시/스냅샷에 `ticketInfo`가 남아 있더라도 앱 UI에서 종료 상태면 한 번 더 숨기도록 방어 처리

---

## 2026-03-31: 에이전트 메모와 저장소 스킬 정리

### 완료
- [x] `AGENTS.md`에 런타임/운영 메모 추가
- [x] `CLAUDE.md`에 동일한 저장소 운영 인사이트 반영
- [x] 반복 가능한 작업을 `.claude/skills/` 로 분리
  - `kbo-runtime-data`
  - `kbo-release-flow`
  - `app-startup-runtime-triage`
  - `ios-device-run-action`

### 반영 인사이트
- 웹/release 는 backend API 경로를 기본으로 사용
- 로컬 네이티브는 direct crawler 경로를 디버깅 목적에 한해 사용 가능
- home first paint 는 경량 payload / cache 우선
- historical standings/records/completed games 는 snapshot 우선
- push 실패 시 `github-personal` SSH alias 경로 사용
- local Android API 연결은 `10.0.2.2` 를 기본값으로 보는 편이 안전함
- 실기기 실행 이슈는 `flutter devices` 와 `xcodebuild -showdestinations` 를 같이 봐야 함

---

## 2026-03-31: 인사이트 문서화 및 Claude 스킬 추출

### 완료
- [x] 최근 캐시/snapshot/문서 동기화 인사이트를 `docs/ENGINEERING_NOTES.md`로 정리
- [x] `.claude/skills/kbo-history-snapshot/SKILL.md` 추가
- [x] `.claude/skills/kbo-doc-sync/SKILL.md` 추가
- [x] `.claude/SKILL_REFERENCE.md` 추가
- [x] `AGENTS.md`, `CLAUDE.md`에 새 인사이트와 skill 진입점 연결

### 원인
- 최근 작업에서 히스토리 데이터 snapshot 우선 전략과 문서 동기화 규칙이 반복적으로 등장했고, 매번 대화로만 유지하면 다음 세션에서 쉽게 누락될 수 있었음
- repo-local Claude skill 체계가 이미 일부 존재했기 때문에, 새로 얻은 반복 패턴도 같은 위치에 편입하는 편이 유지보수에 유리했음

### 비고
- 이번 단계는 코드 실행 경로 변경이 아니라 컨텍스트/워크플로우 정리 작업이다
- 새 skill 은 Claude 로컬 기준 진입점이고, Codex 쪽은 `AGENTS.md`와 문서 연결로 함께 발견 가능하도록 맞췄다

---

## 2026-03-31: 웹 UX/UI 점검 및 10개 페르소나 분석

### 완료
- [x] Flutter 웹 디버그 세션 실제 실행
- [x] `#/onboarding`, `#/home`, `#/schedule`, `#/standings`, `#/settings` 라우트 실측
- [x] 홈 화면 네트워크 호출(`scoreboard`, `schedule`, `standings`, `records/overview`) 확인
- [x] 10개 유저 페르소나 기준 UX/UI 개선점 문서화 (`docs/UX_AUDIT_2026-03-31.md`)
- [x] `README.md`의 웹 플랫폼 존재 여부 문구 최신화
- [x] 웹에서 모바일 화면이 과도하게 늘어나지 않도록 공통 `AppPageFrame` 추가
- [x] 온보딩 카드 밀도와 설명 문구 조정
- [x] 홈 마이팀 미선택 CTA와 오늘의 야구 빠른 액션 보강
- [x] 일정 화면에 달력 범례 추가
- [x] 순위 화면에 마이팀 요약 카드 추가
- [x] 설정 화면에 알림 설명문과 토글별 보조 문구 추가
- [x] 순위/기록실 요약 시즌별 번들 스냅샷 fallback(`2001~현재`) 추가
- [x] 앱 부트스트랩에 timeout/fallback 을 추가해 shared preferences 응답 지연 시 무한 스플래시를 피하도록 보강
- [x] 웹 HTML 스플래시에 DOM 감지/timeout 제거 fallback 추가
- [x] 정적 빌드 기반 `web-static` 프리뷰 스크립트 추가
- [x] 기본 `codex-run-web.sh` 를 정적 프리뷰 기준으로 전환하고 `codex-run-web-dev.sh` 추가
- [x] 게임 상세 UI 의도를 `docs/GAME_DETAIL_UI_NOTES.md` 로 문서화
- [x] 기기 단독모드 디버깅 메모를 `docs/GAME_DETAIL_DEBUG_NOTES.md` 로 문서화

### 확인 사항
- `flutter run -d chrome` 디버그 세션은 정상 렌더링됨
- `flutter run -d web-server --web-port 7357` 는 일반 Chrome 기준으로 Flutter view 가 뜨지 않아 안정적인 검증 경로로 보기 어려움
- 웹 프리뷰는 `./scripts/codex-run-web-static.sh` 또는 `./scripts/codex-run.sh web-static` 기준으로 사용하는 쪽이 안전함
- Codex 액션 기본 웹 실행 경로는 `./scripts/codex-run-web.sh`, Chrome 디버그가 필요하면 `./scripts/codex-run-web-dev.sh`
- 실제 시각 검증 기준으로 홈은 정보 구조가 풍부하지만 첫 화면 우선순위 정리가 더 필요함

### 검증
- [x] `cd app && fvm flutter analyze --no-fatal-infos`
- [x] `cd app && fvm flutter test`

### 비고
- macOS 앱 포커스 경쟁 때문에 기록실/경기 상세는 안정적인 스크린샷 확보가 제한됐고, 해당 영역은 코드 구조와 라우트 접근 가능 여부를 함께 참고해 판단함

## 2026-03-31: 히스토리 데이터 선수집 / 스냅샷 우선 전략 명문화

### 완료
- [x] `docs/APP_SPEC.md`에 live / warm cache / persisted snapshot 3계층 데이터 전략 추가
- [x] 선수 과거 기록, 지난 경기 결과, 지난 날짜 순위를 원천 재크롤링보다 저장된 스냅샷 우선으로 응답한다는 정책 명시
- [x] 선수 상세 / 일정 / 순위 화면 운영 메모에 히스토리 데이터 선계산 및 재검증 원칙 반영
- [x] `README.md`, `CHANGELOG.md`에 로딩 체감 개선을 위한 snapshot 우선 운영 방침 반영

### 원인
- 현재 문서는 홈 `30초 TTL`, 기록실 `5분 TTL` 정도까지만 정의되어 있었고, 과거 데이터까지 매 요청 시점 수집 대상으로 볼 여지가 있었음
- 사용자 경험 관점에서는 지난 경기, 지난 순위, 선수 과거 기록은 앱 진입 즉시 보여야 하고, 이 영역에 매번 크롤링 지연이 걸리면 제품 방향인 "열면 바로 야구"와 충돌함
- KBO 원천 응답은 느리거나 불안정할 수 있어, 종료 경기/히스토리 영역은 수집 시점과 조회 시점을 분리하는 쪽이 운영 안정성에도 유리함

### 비고
- 이번 단계는 문서/아키텍처 결정 반영이며, 실제 DB snapshot 스키마와 배치 작업 구현은 후속 개발 범위다
- 공개 API 계약은 유지하고, 서버 내부 응답 전략을 live cache 중심에서 snapshot 우선 구조로 확장하는 기준만 먼저 확정했다

---

## 2026-03-31: 마이팀 경기 이벤트 로컬 알림 추가

### 완료
- [x] 홈 스코어보드 갱신 시 마이팀 경기 시작 / 득점 / 역전 / 경기 종료를 감지하는 로컬 알림 서비스 추가
- [x] 기존 설정 화면의 `경기 시작 / 득점 / 역전 / 경기 종료` 토글을 로컬 이벤트 감지 기준으로 재사용
- [x] 점수 변화 비교용 스냅샷을 로컬에 저장해 중복 알림을 줄이도록 정리

### 비고
- 이 방식은 원격 푸시가 아니라 앱 실행 중 또는 갱신 주기 시점 기준의 best-effort 로컬 알림임
- 홈 폴링 주기를 따르므로 완전 실시간 보장은 안 됨
- 홈런 전용 알림은 scoreboard만으로는 확정이 어려워 이번 단계에서는 별도 미구현

## 2026-04-01: 로컬 경기 이벤트 알림 확장

### 완료
- [x] `local` 환경에서도 홈 스코어보드 갱신 시 로컬 경기 이벤트 알림이 동작하도록 홈 화면 호출 조건 정리
- [x] 홈런 알림을 relay event 비교 기준으로 구현
- [x] 이닝 교대 알림을 relay `INNING_CHANGE` 비교 기준으로 구현
- [x] 라인업 공개/변경 알림을 lineup signature 비교 기준으로 구현
- [x] 설정 화면에 `라인업`, `이닝 교대` 토글 추가
- [x] push registration payload 와 backend schema 에 `lineupOpened`, `inningChange` 설정값 반영
- [x] `fvm flutter analyze` 대상 파일 무이슈 확인

### 비고
- 로컬 알림은 여전히 앱 refresh 주기 기반 best-effort 이며 서버 push 대체는 아님
- `리그 전체 알림`이 켜져 있으면 마이팀 외 경기에도 동일한 로컬 이벤트 알림을 적용

---

## 2026-03-31: 예매 오픈 로컬 알림 다단계 예약

### 완료
- [x] 예매 오픈 로컬 알림을 하루 전 / 1시간 전 / 10분 전 3단계로 예약하도록 변경
- [x] 예매 알림 해제 시 예약된 3개 리마인드를 모두 취소하도록 정리
- [x] 예약 결과 메시지에 실제로 설정된 리마인드 시점을 표시하도록 보완

---

## 2026-03-31: relay 테스트 안정화 / 상태 라벨 공통화

### 완료
- [x] `tests/test_relay_service.py`가 실제 `RelayCrawler` 네트워크 결과에 흔들리지 않도록 fallback 검증용 failing stub 추가
- [x] 백엔드 전체 `pytest` 기준 `relay_service` 2건 실패 해소
- [x] 앱 상태 라벨 매핑을 공통 유틸로 분리해 일정 화면이 이를 재사용하도록 정리
- [x] 홈/상세 fallback 상태 문구도 공통 상태 라벨 유틸을 재사용하도록 정리
- [x] 홈 spotlight/status chip 과 홈 경기 카드도 공통 상태 배지 컴포넌트를 사용하도록 통일
- [x] 일정 카드 위젯을 분리하고 상태 라벨/점수/서스펜디드 정책 회귀 방지 widget test 추가
- [x] 일정 카드 골든 테스트와 기준 이미지 추가
- [x] 날짜별 스코어보드 응답을 30초 TTL 캐시에 보관하고 경기별 enrich 를 병렬화해 홈 재진입 속도 개선
- [x] 홈/기록실 실측 지표를 `/api/metrics/client` 로 서버에 전송하고 `backend/logs/client_metrics.log` 에 저장하도록 추가
- [x] KBO 원본 호출 공통 베이스에 circuit breaker 를 넣고 주요 홈/기록실 경로 crawler 를 이를 사용하도록 정리
- [x] scoreboard / team stats / team players 에 stale cache fallback 을 추가해 KBO 원본 실패 시 직전 정상 응답을 재사용하도록 보강
- [x] 웹 `API 진단` 화면을 추가해 `health / scoreboard / schedule` 상태를 한 번에 확인 가능하도록 구현
- [x] README / APP_SPEC 에 운영 메모, 캐시 TTL, 로그 위치, 진단 화면 정보를 반영
- [x] 친구/테스터 배포 경로를 정리한 `docs/DISTRIBUTION_GUIDE.md` 추가
- [x] `docs/DISTRIBUTION_GUIDE.md`에 iOS TestFlight / Android 내부 테스트 실제 업로드 순서 추가
- [x] `docs/ANDROID_SIGNING_GUIDE.md` 추가
- [x] `docs/IOS_TESTFLIGHT_CHECKLIST.md` 추가
- [x] Android release signing 을 `key.properties` 기반 구조로 정리
- [x] `.claude/skills/app-distribution/SKILL.md` 추가
- [x] `.claude/SKILL_REFERENCE.md`에 `app-distribution` 추가
- [x] 배포 / 액션 등록 관련 인사이트를 `AGENTS.md`, `CLAUDE.md`에 반영
- [x] 구현 인사이트 정리용 `docs/ENGINEERING_NOTES.md` 추가
- [x] 반복 작업을 위한 `.claude/skills/ios-live-activity-widget`, `.claude/skills/mobile-preview-release` 추가
- [x] `AGENTS.md`, `CLAUDE.md` 에 문서/스킬 진입점 반영

### 검증
- [x] `cd backend && source .venv/bin/activate && pytest -q`
- [x] `cd app && fvm flutter analyze --no-fatal-infos`
- [x] `cd app && fvm flutter test test/features/schedule/widgets/schedule_game_card_test.dart`
- [x] `cd app && fvm flutter test test/features/schedule/widgets/schedule_game_card_golden_test.dart`
- [x] `/api/scoreboard?date=2026-03-31` 실측
  - 첫 호출: 약 0.184초
  - 캐시 적중 후: 약 0.003초

---

## 2026-03-30: 홈 화면 브리프/요약 구조 1차 추가

### 완료
- [x] 홈 상단에 `마이팀 브리프` 카드 추가
- [x] 홈 상단에 `오늘의 야구` 요약 카드 추가
- [x] 홈 상단에 `빠른 콘텐츠` 카드 섹션 추가
- [x] 경기 없는 날에도 홈이 비어 보이지 않도록 빈 상태 구조를 브리프 중심으로 보완
- [x] 홈 브리프 데이터에 마이팀 순위, 최근 흐름, 리그 리더/오늘의 플레이어 요약 반영

### 원인
- 기존 홈은 사실상 스코어보드 전용 화면이라 경기 없는 날이나 마이팀 경기가 없는 날에 화면이 지나치게 비어 보였음
- 앱을 열자마자 야구 맥락이 전달되기보다, 경기 카드가 없으면 볼 정보가 거의 없었음

### 검증
- [x] `cd app && fvm flutter analyze --no-fatal-infos`
- [x] `cd app && fvm flutter test`
- [x] 웹에서 홈 화면 브리프 카드 렌더링 확인

---

## 2026-03-31: 원격 푸시 경로 연결

### 완료
- [x] 앱에 Firebase 초기화 및 FCM 토큰/토픽 동기화 서비스 추가
- [x] 마이팀 변경 시 푸시 토픽 재구독 및 `/api/push/register` 재등록 연결
- [x] 설정 화면 알림 토글을 SharedPreferences에 저장하고 푸시 구독과 연동
- [x] Android 13+ `POST_NOTIFICATIONS` 권한 선언 추가
- [x] 백엔드 `/api/push/test` 테스트 발송 endpoint 추가
- [x] 백엔드 Firebase Admin 서비스 계정 경로/프로젝트 ID 설정 추가
- [x] 진단 화면에 푸시 초기화/토픽 상태 표시 추가

### 비고
- 실제 원격 푸시 수신까지는 앱의 Firebase 설정 파일(`GoogleService-Info.plist`, `google-services.json`)과 백엔드 서비스 계정 JSON이 필요
- 현재 코드 경로는 연결됐지만, 위 설정 파일이 없으면 런타임에서 초기화가 skip 될 수 있음

---

## 2026-03-30: 웹 하이라이트 재생 시 스크롤 잠김 수정

### 완료
- [x] 기록실 첫 화면 리더보드에 리그 홈런 순위 추가
- [x] 웹에서 하이라이트 인라인 재생 후 페이지 스크롤이 막히던 문제 수정
- [x] 웹 하이라이트를 인라인 재생하면서도 `스크롤 / 플레이어 조작` 모드 전환으로 스크롤 충돌을 피하도록 조정
- [x] 하이라이트 안내 문구와 버튼 라벨을 웹 동작에 맞게 조정

---

## 2026-03-30: 최초 로딩 체감 속도 개선

### 완료
- [x] 백엔드 `/api/scoreboard`가 `yyyyMMdd` 형식 날짜도 허용하도록 보강해 웹 홈 화면 날짜 포맷 예외 제거
- [x] 앱 시작 직후 홈, 일정, 순위, 기록실 핵심 데이터를 백그라운드 prefetch 하도록 조정
- [x] 기록실 팀 화면이 선수 목록과 팀 스탯을 별도 API 2개로 기다리지 않고 `/api/team/{teamId}/records` 합본 응답을 사용하도록 정리
- [x] 백엔드 기록실 크롤러에서 포지션별 선수 검색과 팀 타격/투수 스탯 수집을 병렬화해 최초 로딩 대기시간을 단축
- [x] 백엔드 `/api/team/{teamId}/records` endpoint 및 테스트 추가
- [x] 팀/시즌 기준 기록실 응답을 서비스 메모리 캐시에 5분 보관해 재진입 속도 개선
- [x] 웹 실행 검증 중 드러난 경기 상세 라인업 탭 파일 누락/생성자 불일치 문제 수정
- [x] 종료 경기 relay는 crawler 원문 대신 scoreboard 기반 summary relay를 우선 사용하도록 정리
- [x] live relay에서 crawler currentAtBat 가 비어 있으면 scoreboard current 정보로 보강하도록 수정
- [x] 예정 경기 `GetScoreBoardScroll` 응답에 `table2/table3` 가 없어도 홈 `/api/scoreboard` 가 500 없이 내려오도록 보강
- [x] 예정 경기 scoreboard fallback 에서 `inning` 이 `경기중` 으로 잘못 내려오지 않도록 `예정` 문구로 보정
- [x] 홈/순위 화면에서 raw `DioException` 대신 사용자용 에러 문구를 표시하도록 정리
- [x] 앱 API 요청 시간을 Dev Console 에 기록해 홈/기록실 병목을 확인할 수 있도록 보강
- [x] 기록실 서비스 캐시를 공통 TTL 캐시 유틸로 정리
- [x] 예정 경기에서는 YouTube 하이라이트 검색을 건너뛰어 불필요한 외부 요청 제거

### 원인
- 웹 검증 중 홈 화면 `scoreboard` 호출이 `20260330`처럼 하이픈 없는 날짜를 보내는 케이스가 확인됐고, 백엔드 `schedule` 조회는 `yyyy-MM-dd`만 가정하고 있었음
- 앱은 첫 진입 시 화면별로 필요한 데이터를 사용 시점에만 요청해서 하단 탭 첫 방문마다 네트워크 대기가 그대로 노출되고 있었음
- 기록실 팀 화면은 선수 목록과 팀 스탯을 각각 별도 요청으로 받았고, 백엔드도 일부 KBO 수집을 직렬로 처리하고 있었음
- 이 구조 때문에 기록실은 물론 일정/순위도 앱 실행 직후 첫 방문 체감이 무거웠음
- 실제 측정 결과 `LG` 기록실 합본 응답은 콜드 기준 약 8~11초가 걸려, 같은 팀 재진입도 서버 재수집이 반복되면 개선 폭이 작았음
- 웹 실행 검증 과정에서 `game_detail_screen.dart` 가 삭제된 `lineup_tab.dart` 를 import 하고 있어 앱 빌드 자체가 실패하고 있었음
- relay 서비스는 crawler 결과가 존재하면 그대로 반환하고 있었는데, 종료 경기에서는 테스트/UX가 기대하는 요약형 흐름과 다르게 원문 이닝 체인지 로그가 우선 노출될 수 있었음
- live 경기에서는 crawler 가 currentAtBat 를 비워 반환하는 경우에도 scoreboard current 정보로 보강하지 않아 현재 타석 정보가 비는 케이스가 있었음
- 홈 화면은 `/api/scoreboard` 를 직접 보는데, 예정 경기의 KBO scoreboard payload 에 `table2/table3` 가 없을 때 crawler 가 이를 무조건 참조하면서 `KeyError: table2` 로 500이 발생하고 있었음
- 홈 화면 에러 UI가 raw `DioException` 문자열을 그대로 노출하고 있어 사용자 관점에서 원인 파악이 어려웠음
- 기록실 캐시는 서비스별로 개별 구현이 중복돼 있어 TTL 정책을 바꾸거나 확장할 때 손볼 지점이 두 군데였음
- 예정 경기 scoreboard 에서도 YouTube 검색을 수행하고 있어 홈 첫 로딩 때 불필요한 외부 호출이 섞이고 있었음

### 검증
- [x] `cd backend && source .venv/bin/activate && pytest -q tests/test_teams.py`
- [x] `cd app && fvm flutter analyze --no-fatal-infos`
- [x] `http://127.0.0.1:3101/#/home`, `http://127.0.0.1:3101/#/records/team/LG` 웹 실행 확인
- [x] `http://127.0.0.1:8010/api/team/LG/records?season=2026` 응답 시간 측정
  - 첫 요청: 약 8.64초
  - 두 번째 요청: 0초대
- [x] `cd backend && source .venv/bin/activate && pytest -q`
- [x] `source .venv/bin/activate && PYTHONPATH=src python -c 'from kbo_fans_backend.services.scoreboard import ScoreboardService; print(ScoreboardService().get_scoreboard("2026-03-31")["games"][0]["status"])'`
- [x] `cd app && fvm flutter analyze --no-fatal-infos`

---

## 2026-03-30: 웹 기능 점검 및 기록실/설정 버그 수정

### 완료
- [x] Flutter 웹 앱을 실제 브라우저에서 실행해 홈, 일정, 경기 상세, 기록실, 설정 흐름 점검
- [x] 기록실 팀 선택 화면이 구단 10개의 선수 API를 동시에 호출하던 구조를 제거
- [x] 기록실 첫 화면에서 리그 리더보드/추천 선수만 먼저 보여주고, 팀 상세 진입 시에만 선수 데이터를 조회하도록 정리
- [x] 기록실 팀 상세가 웹에서 10초 API 타임아웃으로 비정상 실패하던 문제를 완화하기 위해 앱 API 타임아웃을 25초로 조정
- [x] 설정 화면의 `전체 경기 알림` 안내 문구가 스위치 상태와 반대로 보이던 문제 수정
- [x] 하이라이트 카드 타입/색상 처리, 미사용 import, deprecated API 사용 정리로 웹 analyze 경고 제거

### 원인
- 기록실 팀 선택 카드가 요약 문구를 만들기 위해 각 팀별 `teamPlayersProvider`를 모두 `watch`하고 있었음
- 웹에서는 첫 진입 시 `/api/team/{teamId}/players` 요청이 한꺼번에 발생해 타임아웃과 콘솔 노이즈가 생겼음
- KBO 크롤링 기반 선수/기록 API는 응답이 10초를 넘는 경우가 있어, 웹 Dio 클라이언트가 백엔드보다 먼저 요청을 중단하고 있었음
- 설정 화면은 `전체 경기 알림`이 꺼진 상태에서만 `마이팀 외 경기도 알림을 받습니다` 문구를 노출해 의미가 뒤집혀 있었음

### 검증
- [x] `cd app && fvm flutter analyze --no-fatal-infos`
- [x] `cd app && fvm flutter test`
- [x] Playwright로 `#/records`, `#/settings`, `#/schedule`, 경기 상세 화면 렌더링 확인
- [x] 기록실 첫 화면 재검증 시 팀별 선수 API 연속 호출/콘솔 에러가 사라진 것 확인
- [x] 기록실 팀 상세/선수 상세 재검증 시 웹에서 정상 렌더링되는 것 확인

### 비고
- 당시 `tests/test_relay_service.py` 2건 실패는 이후 `2026-03-31` 항목에서 fallback stub 추가로 정리됨

---

## 2026-03-30: 일정 카드 상태 문구 / 점수 표시 보강

### 완료
- [x] KBO 월간 일정 원본 `play_html`에서 경기 점수 파싱 추가
- [x] 백엔드 `/api/schedule` 응답에 `awayScore`, `homeScore` 필드 포함
- [x] 일정 화면 카드 상태 문구를 `경기 전 / 경기 중 / 경기 종료`로 통일
- [x] 일정 화면 카드 중앙 영역에 점수가 있으면 `awayScore : homeScore`, 없으면 `vs`를 표시하도록 수정
- [x] 관련 일정 화면 명세를 `docs/APP_SPEC.md`에 반영

### 비고
- KBO 월간 일정 원본은 종료 경기 점수를 직접 포함하고 있어 추가 scoreboard API 호출 없이 카드 점수 노출이 가능함
- 예정 경기는 점수 데이터가 없으므로 기존처럼 `vs`를 유지

---

## 2026-03-30: 종료 경기 상세 진입 오류 수정

### 완료
- [x] 일정 화면에서 `extra` 없이 상세 화면에 진입해도 `gameId` 기반 재조회로 경기 상세를 열 수 있도록 수정
- [x] 앱 상세 화면이 `state.extra` 의존으로 바로 실패하던 흐름을 Riverpod `gameProvider` 조회 기반으로 보완
- [x] 백엔드에 누락되어 있던 `/game/{gameId}` 단건 조회 endpoint 추가
- [x] 종료 경기에서도 경기 결과/박스스코어/라인업 진입이 가능하도록 앱-백엔드 상세 조회 경로 정리
- [x] 미구현 상태인 문자중계 API가 raw 에러로 노출되지 않도록 상태별 안내 문구로 대체
- [x] 문자중계 탭이 `relay` endpoint를 중복 호출하던 구조를 단일 호출로 정리
- [x] 백엔드 `relay` endpoint가 501 대신 빈 payload를 반환하도록 정리해 웹 콘솔 오류 제거
- [x] 예정 경기 `section=START_PIT` 링크를 `SCHEDULED`로 분류하도록 일정 상태 파싱 보정
- [x] 종료 경기 문자중계 탭에서 이닝별 득점 요약과 경기 종료 결과를 보여주는 summary relay 추가
- [x] KBO 로그인 세션을 사용하는 `LiveTextView2.aspx` crawler 추가
- [x] `KBO_RELAY_USER_ID` / `KBO_RELAY_PASSWORD` 환경변수 기반으로 실제 play-by-play relay 파싱 지원
- [x] `backend/.env` 자동 로드 지원 추가
- [x] 로컬 `backend/.env`에 KBO relay 계정 설정
- [x] 라인업 탭을 모바일 카드형 UI로 전면 정리
- [x] 라인업 탭 상단 스위처에 `AWAY/HOME + 팀명 + 로고` 표시 추가
- [x] 홈 진입 속도 개선을 위해 scoreboard 응답에서 유튜브 하이라이트 검색 제거
- [x] iOS/Android 런치 스크린을 다크 테마로 정리해 초기 흰 화면 노출 완화

### 원인
- 홈 화면은 `/game/:gameId` 라우팅 시 `extra: game`을 넘기지만, 일정 화면은 `gameId`만 넘기고 있었음
- `GameDetailScreen`이 `game == null`이면 즉시 `경기를 찾을 수 없습니다`를 렌더링하고 있었음
- 웹/릴리즈용 `ApiGameRepository.getGame()`가 호출하는 `/game/{gameId}` 백엔드 라우트가 실제로 없었음
- `/game/{gameId}/relay`는 아직 백엔드 미구현이라 상세 탭에서 사용자에게 실패 문구가 그대로 노출되고 있었음
- 앱에서 `relayProvider`와 `currentAtBatProvider`가 같은 endpoint를 각각 호출해 같은 실패가 중복 발생하고 있었음
- KBO 일정 응답에서 예정 경기가 `section=START_PIT`로 내려오는 케이스를 `SCHEDULED`로 분류하지 못해 상세 상태가 `UNKNOWN`으로 내려오고 있었음
- KBO 공식 live relay 원본 경로를 즉시 안정적으로 확보하기 어려워, 종료 경기의 경우 scoreboard 데이터로부터 흐름 요약을 만들어 탭 공백을 줄일 필요가 있었음
- KBO 공식 `문자중계보기`는 로그인 사용자에게만 `LiveText.aspx` / `LiveTextView1.aspx` / `LiveTextView2.aspx`를 정상 제공하고 있었음

---

## 2026-03-30: 예매 정보 / 예매 오픈 알림 추가

### 완료
- [x] 일정 화면 카드에 경기별 예매처와 예매 오픈 시간 표시 추가
- [x] 경기 상세 상단에 예매 정보 카드 추가
- [x] 경기 상세에서 예매처 외부 링크 열기 버튼 추가
- [x] 경기 상세에서 경기별 예매 오픈 알림 토글 추가
- [x] 디바이스 로컬 알림 기반 예매 오픈 시각 예약 알림 구현
- [x] 백엔드 `/api/schedule`, `/api/game/{gameId}`, `/api/scoreboard` 응답에 `ticketInfo` 필드 추가
- [x] 경기 상세 상단에 KBO 공식 / 유튜브 하이라이트 카드 추가
- [x] 백엔드에서 KBO 공식 링크 + 유튜브 검색 기반 `highlightInfo` 메타데이터 조회 추가
- [x] 하이라이트 카드에서 KBO 공식 페이지와 유튜브 웹 페이지를 각각 열 수 있도록 추가
- [x] 스코어 탭 이닝 셀 클릭 시 해당 회차 주요 장면 바텀시트 추가
- [x] 문자중계 탭이 라이브 경기 전용으로 막히지 않도록 완화
- [x] 라인업/상세 탭 좁은 폭 깨짐 대응을 위해 가로 스크롤 보강
- [x] 홈 스코어보드 기준 위젯 동기화 서비스 추가
- [x] 앱 foreground 기준 라이브 30초 / 예정 5분 자동 갱신 추가
- [x] Android 앱 위젯 리시버 / 레이아웃 / 15분 주기 background refresh 등록 추가
- [x] iOS WidgetKit용 데이터 공유/배경 갱신 훅 및 위젯 소스 초안 추가
- [x] 반복 패턴을 `.claude/skills/` 로 승격 (`kbo-asmx-direct-integration`)
- [x] AGENTS / CLAUDE / SKILL_REFERENCE 에 재사용 인사이트 동기화
- [x] 앱 단독 모드 전환 현황 문서 추가 (`docs/APP_STANDALONE_MODE.md`)

### 한계
- Android 위젯의 시스템 `updatePeriodMillis`는 30분 미만으로 내려갈 수 없어서 15분 주기는 Workmanager 기반 best-effort로 보강
- iOS WidgetKit은 시스템 budget 기반이라 실시간/초단위 갱신을 보장하지 않음
- 현재 relay API는 투구별 원문 중계가 아니라 회차별 점수 요약 이벤트 중심

### 비고
- KBO 일정 원본 응답에는 예매처/예매 오픈 시간이 없어 현재는 홈팀 기본 정책 기준 추정값으로 내려줌
- 실제 운영 단계에서는 팀별 공식 예매 페이지 크롤링 또는 별도 관리 데이터가 필요
- 웹에서는 로컬 예약 알림을 지원하지 않음

---

## 2026-03-30: 기록실 / 선수 상세 화면 추가

### 완료
- [x] 하단 탭에 `기록실` 추가
- [x] 마이팀 기준 선수 리스트 화면 추가
- [x] `전체 / 엔트리 / 엔트리 제외` 필터 추가
- [x] 선수 카드에 부상 / 엔트리 제외 상태 배지와 간단 기록 표시
- [x] 선수 프로필 / 시즌 기록 / 최근 기록을 보여주는 상세 화면 추가
- [x] 기록실에 `야수 / 투수` 탭 분리 추가
- [x] `타율 / OPS / ERA / WHIP` 기준 정렬 추가
- [x] 백엔드 `team players`, `player detail` API 추가
- [x] KBO 공식 등록 현황 / 선수 상세 기록 페이지 기반 크롤링 연결
- [x] 관련 문서(`README.md`, `CHANGELOG.md`, `docs/APP_SPEC.md`) 반영

### 비고
- 웹/릴리즈 기록실은 실제 백엔드 선수 API를 사용
- 네이티브 로컬 환경은 현재 mock fallback 유지
- KBO 공식 페이지에서 부상 사유를 직접 주지 않아 `말소 = 엔트리 제외`로 우선 표시

---

## 2026-03-30: README / CHANGELOG 정리

### 완료
- [x] 루트 `README.md` 신규 작성
- [x] 루트 `CHANGELOG.md` 신규 작성
- [x] Codex 앱 실행 액션용 `scripts/codex-run.sh` 추가
- [x] 저장소 실행 방법, 문서 우선순위, 현재 구현 범위를 루트 README에 정리
- [x] `AGENTS.md`에 README / CHANGELOG 지속 갱신 규칙 추가
- [x] `CLAUDE.md`에 README / CHANGELOG 문서 역할 및 갱신 규칙 추가
- [x] README에 Codex 앱 실행 액션 등록용 명령 추가

### 반영 원칙
- 이후 실행 방법, 현재 구현 범위, 저장소 구조가 바뀌면 `README.md`를 같이 갱신
- 이후 사용자 관점 기능 변화나 마일스톤 변화가 생기면 `CHANGELOG.md`를 같이 갱신

### 추가 수정
- [x] 백엔드 `int | None` 등 Python 3.10+ 타입 문법을 Python 3.9 호환 표기로 정리
- [x] `uvicorn` 실행 시 FastAPI import 단계에서 발생하던 타입 평가 오류 수정
- [x] `AGENTS.md`, `CLAUDE.md`에 Python 3.9 호환 타입 힌트 규칙 명시
- [x] Firebase iOS plugin 호환을 위해 iOS deployment target을 `15.0`으로 상향
- [x] Flutter web 플랫폼 추가 (`app/web`)
- [x] `scripts/codex-run.sh web` 실행 경로 추가
- [x] Codex 실행 액션용 플랫폼 분리 스크립트 추가 (`ios`, `android`, `web`)
- [x] iOS Xcode 프로젝트의 `SDKROOT` / `SUPPORTED_PLATFORMS`를 시뮬레이터 호환으로 정리

---

## 2026-03-30: AGENTS 컨텍스트 동기화

### 완료
- [x] `CLAUDE.md` 기반 `AGENTS.md` 신규 작성
- [x] 저장소 내 Markdown 문서 전체 재검토 (`CLAUDE.md`, `docs/PLANNING.md`, `docs/APP_SPEC.md`, `docs/WORKLOG.md`)
- [x] 문서 간 기준 우선순위 정리 (`AGENTS.md`에 반영)
- [x] 최신 모바일 스택 기준이 Flutter임을 재확인

### 확인 사항
- `docs/PLANNING.md` 마지막 "다음 단계" 항목의 `Expo 프로젝트 셋업` 문구를 `Flutter 프로젝트 셋업`으로 정정
- 최신 기준은 `Flutter + Dart`, `Riverpod`, `go_router`, `dio`, `FastAPI`, `AWS`, `FCM`

### 비고
- 이후 작업은 `AGENTS.md`를 기본 작업 가이드로 사용

### 추가 진행
- [x] `docs/FIGMA_PROMPT.md` 전체 검토
- [x] Figma 작업 스킬 및 대상 파일 접근 경로 확인

### 현재 블로커
- Figma MCP 조회 시 Starter 플랜 도구 호출 한도 초과로 파일 메타데이터 조회 실패
- 오류 메시지 기준 추가 작업 전 Figma MCP 한도 초기화 또는 상위 플랜 필요

### 추가 문서 정리
- [x] `docs/FIGMA_PROMPT.md` 반영해 `CLAUDE.md` 보강
- [x] `docs/FIGMA_PROMPT.md`와 최근 작업 상황 반영해 `AGENTS.md` 보강
- [x] `docs/TASK_DIVISION.md`를 협업 운영 문서 형태로 재정리

### 백엔드 착수
- [x] FastAPI 백엔드 기본 구조 생성 (`backend/`)
- [x] `pyproject.toml`, `.env.example`, `README.md` 추가
- [x] `api / core / crawlers / scheduler / push / schemas / utils` 패키지 골격 생성
- [x] `/api/health` 구현 및 나머지 제품 API 스텁 라우트 등록
- [x] 기본 테스트 파일 추가 (`backend/tests/test_health.py`)
- [x] `GetScheduleList` 기반 월간 일정 크롤러 구현
- [x] `GetScoreBoardScroll` 기반 스코어보드 상세 크롤러 구현
- [x] `GetBoxScoreScroll` 기반 박스스코어 크롤러 구현
- [x] `GetLineUpAnalysis` 기반 라인업 크롤러 구현
- [x] TeamRankDaily SSR 파싱 기반 순위 크롤러 구현
- [x] `/api/scoreboard`, `/api/schedule`, `/api/game/{gameId}/boxscore`, `/api/game/{gameId}/lineup`, `/api/standings` 연결
- [x] `/api/push/register` 성공 응답 구현

### 검증
- [x] `python3 -m compileall backend/src` 통과
- [x] 서비스 레벨에서 schedule/scoreboard/boxscore/lineup/standings 응답 샘플 확인

### 남은 백엔드 작업
- [ ] 문자중계 실제 데이터 경로 확인 및 `relay` 구현
- [ ] push/register 실제 FCM 연동 구현

---

## 2026-03-28: 프로젝트 초기 세팅 + 기획 완료

### 완료
- [x] Git 레포 생성 (godekd3133/kbo-fans, Private)
- [x] SSH 설정 (`github-personal` alias → `~/.ssh/andy` 키 → godekd3133)
- [x] `.gitignore` 작성
- [x] `CLAUDE.md` 프로젝트 컨텍스트 작성
- [x] `docs/PLANNING.md` 서비스 기획서 작성 (경쟁사 상세 분석 + 차별화 전략 포함)
- [x] `docs/APP_SPEC.md` 앱 상세 기획서 작성 (화면 6개 와이어프레임 + API 7개 명세)
- [x] `design_docs.docx` 수업 제출용 기획서 채움 (팀 정보, 기능 명세, 화면 목록, 패키지, 일정)
- [x] `docs/WORKLOG.md` 작업 이력 문서 생성

### 결정 사항
- **프레임워크**: Flutter + Dart (수업 필수 요구사항)
- **타겟 사용자**: 코어팬 + 라이트팬 모두
- **서비스 목표**: 앱스토어 출시
- **MVP 기능 4개**: 실시간 스코어보드, 문자중계, 박스스코어, 푸시 알림
- **백엔드 인프라**: AWS (EC2/ECS + RDS PostgreSQL + ElastiCache Redis)
- **상태관리**: Riverpod
- **라우팅**: go_router
- **HTTP**: dio

### 변경 이력
- React Native (Expo) → **Flutter (Dart)** 로 변경 (수업 요구사항)
- 인프라 미정 → **AWS** 로 확정
- 경쟁사 분석: 네이버 스포츠, SPORTS.i, 야구보구, ESPN 상세 분석 추가
- 차별화 전략 6가지 수립

### 파일 구조
```
kbo_fans/
├── CLAUDE.md
├── design_docs.docx
├── docs/
│   ├── PLANNING.md
│   ├── APP_SPEC.md
│   └── WORKLOG.md
```

### Figma
- 디자인 파일: https://www.figma.com/design/VZdeXTfwxJYBxy2xOJrl8c/Kbo-Fans
- Figma MCP 서버 연결 필요 (현재 미연결 상태)

### 다음 할 일
- [ ] Figma MCP 서버 연결 → 와이어프레임 직접 생성
- [ ] Flutter 프로젝트 셋업 (flutter create)
- [ ] 백엔드 프로젝트 구조 셋업 (FastAPI)
- [ ] 크롤링 프로토타입 (스코어보드 + 문자중계)
- [ ] 스코어보드 화면 구현

---

## 2026-03-31

### 작업 내용
- [x] native 앱 기본 데이터 경로를 `direct KBO only`에서 `API first + direct fallback` 구조로 전환해 홈/상세/relay/lineup이 같은 서버 응답을 우선 사용하도록 정리
- [x] 홈 스코어보드 live 경기에서 `H/E/B`가 0으로 보이던 문제를 수정하기 위해 backend scoreboard service에 `LiveTextView1.aspx` totals fallback 추가
- [x] live 경기 scoreboard 응답에서 `예정/경기중` 같은 뭉툭한 inning 문구 대신 `Main.asmx` 기준 현재 이닝(`8회말` 등)이 우선되도록 merge 순서 정리
- [x] 종료 경기 relay가 득점 요약만 내려오던 문제를 수정해 final 상태에서도 crawler 원문 play-by-play를 우선 시도하고, 실패 시에만 summary fallback 사용
- [x] 문자중계 회차 칩 점프가 lazy sliver 문맥에서 실패하던 문제를 수정하기 위해 relay 카드 렌더를 전체 Column 구조로 변경
- [x] 경기 상세 `문자중계` 탭의 현재 타석 카드를 이닝/주자/타자/투수/투구수/BSO와 최근 교체/직전 플레이가 함께 보이도록 재구성
- [x] relay 목록을 최신 seq 기준 역순 정렬하고, 타석 결과 카드에 이벤트 배지와 플레이 주체 텍스트를 추가
- [x] 웹 검증 중 발견된 경기 상세 `박스스코어` / `라인업` 500 오류 수정
- [x] 예정 경기에서 KBO 박스스코어 응답 키가 없을 때 빈 데이터로 정상 응답하도록 방어 로직 추가
- [x] 기록실 팀 상세 `/team/{teamId}/records`가 선수 크롤링 타임아웃으로 전체 500이 되던 문제를 부분 성공 응답으로 변경
- [x] 팀 선수 목록 크롤링을 경량화해 `/team/{teamId}/players` 및 `/team/{teamId}/records` 응답 시간 단축
- [x] 기록실 overview 서비스에 TTL 캐시 추가
- [x] 기록실 overview featured 카드 생성 시 선수 상세 크롤링 제거 및 리더보드 병렬 수집 적용
- [x] 현재 월 일정 API에 TTL 캐시 추가
- [x] 홈 보조 섹션을 `마이팀/핵심 카드`와 `overview 카드`로 분리해 첫 체감 렌더를 앞당김
- [x] 경기 상세에서 `boxscore` / `lineup` 중복 API 호출을 provider 공유 구조로 제거
- [x] 예정/종료/취소 경기 relay 요청 시 크롤러를 타지 않도록 short-circuit 처리
- [x] records overview 영속 snapshot fallback 추가
- [x] 앱 로컬 API 캐시를 TTL 기반으로 조정해 신선한 데이터 재사용 시 불필요한 백그라운드 재요청 제거
- [x] 홈 화면에서 `schedule` / `standings` 중복 구독 제거
- [x] 홈 `overview` 섹션을 실제 노출 위치 기준으로 lazy load
- [x] 홈 secondary 섹션 전용 aggregate endpoint (`GET /api/home`) 추가
- [x] 홈 화면에서 aggregate 성공 시 secondary 섹션을 서버 조합 데이터로 렌더, 실패 시 기존 provider 조합 fallback 유지
- [x] 관련 백엔드 회귀 테스트 추가
- [x] iPhone local 디버그에서 `records`가 mock/localhost 경로로 빠지던 분기를 제거하고 iOS local 기본 API를 dev 서버로 전환
- [x] direct KBO 일정 파서가 당일 예정 경기 행의 빈 action 셀 때문에 `gameId`를 잃고 오늘 경기 전체를 누락하던 문제 수정
- [x] direct KBO 일정에서 링크가 비어 있어도 날짜+팀명으로 `gameId`를 복원하도록 보강
- [x] local iPhone에서 backend 없이도 `Main.asmx` 기반 live 상태 판정과 `LiveTextView2.aspx` 기반 문자중계를 직접 파싱하도록 direct KBO 경로 보강
- [x] direct relay용 KBO 로그인 플로우를 앱 내부에 추가하고 live scoreboard fallback을 `Main.asmx` 메타데이터로 보강

### 검증 메모
- `GET /api/game/20260331HTLG0/boxscore` : `500` -> `200` (예정 경기 빈 데이터 응답)
- `GET /api/game/20260331HTLG0/lineup` : `500` -> `200`
- `GET /api/team/LG/records?season=2026` : `500` -> `200`
- `GET /api/team/LG/players?season=2026` : 약 `19s` -> 약 `3.7s`
- `GET /api/team/LG/records?season=2026` : 약 `10s+` 실패 -> 약 `3.2s`
- `GET /api/records/overview?season=2026` : 약 `4~6s` -> 약 `1.1s`, 캐시 히트 시 `0.01s` 이내
- 홈 화면은 보조 섹션을 한 번에 기다리지 않고 순차 노출되도록 조정
- `GET /api/game/20260331HTLG0/relay` : non-live 경기에서 크롤러 우회, 약 `0.56s`
- `GET /api/game/20260331HTLG0/boxscore` : 캐시 히트 기준 약 `0.20s`
- 앱 재진입/탭 재방문 시 `schedule`, `standings`, `records`, `player detail`, `overview`는 TTL 내 네트워크 재호출 없이 로컬 캐시 우선 사용
- 홈 화면은 `schedule` / `standings`를 한 번만 읽고 두 섹션에서 재사용
- 홈 `overview`는 고정 시간 지연 대신 실제 화면 근접 시점에 로드
- `GET /api/home?date=2026-03-31&myTeam=LG` : `200`, 약 `0.66s`
- KBO `GetScheduleList` 2026-03 응답에서 `03.31(화)` 예정 경기 행은 review/relay 링크가 비어 있어 기존 파서가 `gameId`를 빈 값으로 처리하던 것을 확인
- KBO `Main.asmx/GetKboGameList` 2026-03-31 응답에서 `GAME_STATE_SC=2` 와 현재 타석 count 필드가 live 판정 근거로 유효함을 확인
- KBO `LiveTextView2.aspx` 20260331OBSS0 응답이 로그인 후가 아닌 direct 호출에서도 relay markup(`#numCont*`, `.playerBox`, `p.present`)을 반환하는 것을 확인
- live direct lineup에서 `GetLineUpAnalysis`는 타선만 제공하고 선발명은 비운다는 점을 확인하고, `Main.asmx/GetKboGameList`의 `T_PIT_P_NM/B_PIT_P_NM` 및 relay 현재 투수로 선발/불펜 fallback 합성 로직을 추가
- live relay 교체 문구(`투수 오러클린 : 투수 백정현 (으)로 교체`)에서 불펜 투수 순서를 복원할 수 있음을 확인하고, local direct 라인업 탭 투수 fallback에 relay 기반 불펜 목록을 연결
- direct boxscore fallback에도 `투수 운용`과 `라인업 기준 타순` 섹션을 추가해 공식 박스스코어 payload가 비어도 라이브 경기 맥락을 유지하도록 보강
- 기록실/선수 데이터 로딩은 모바일 local에서도 `API -> 기기 로컬 snapshot -> 번들 asset` 순서로 동작하도록 `DeviceSnapshotPlayerRepository`를 추가
- `fvm flutter analyze --no-fatal-infos` 통과

### 문서화
- [x] `docs/APP_SPEC.md` 문자중계 탭 UI 요소 설명을 최신 relay 카드 구조 기준으로 갱신
- [x] `docs/APP_SPEC.md`에 종료 경기 relay의 full play-by-play 우선 / summary fallback 정책 반영
- [x] 홈 전용 aggregate endpoint 기반 성능 개선 제안서 작성 (`docs/PERFORMANCE_PROPOSAL_HOME_AGGREGATE.md`)
- [x] 홈 aggregate endpoint 구현 계획서 작성 (`docs/PERFORMANCE_IMPLEMENTATION_PLAN_HOME_AGGREGATE.md`)

### 후속 확인 필요
- [ ] local Android/iOS 기기 단독모드에서 앱 시작 직후 종료가 재발하지 않는지 확인
- [ ] local standalone에서 위젯 / Live Activity / 로컬 알림이 실제로 동작하는지 확인
- [ ] direct KBO `SR_ID` 기반 요청 변경 후 점수판 H/E/B, 이닝별 점수, 라인업, 박스스코어가 실경기 기준으로 안정화됐는지 확인
- [ ] direct relay 현재 타석 카드의 팀 로고 / 선수 프로필 이미지 렌더가 실제 기기에서 정상인지 확인

- [x] iOS 런치 스크린 문구를 단순화하고, AppDelegate/Flutter 첫 프레임 startup 타이밍 로그를 추가해 첫 프레임 이전 지연 구간을 구분 가능하게 함
- [x] 최초 startup preload는 API 캐시/스냅샷을 경기·일정·순위·리그 기록·전 팀 기록실·당일 경기 상세까지 순차 저장하고, Flutter boot 화면은 진행 상태를 단계별로 계속 갱신하도록 조정
- [x] direct KBO 일정 월 조회에서 비정형 row 한 건으로 `Bad state: No element` 가 월 전체 로딩을 깨지지 않도록 row 단위 예외 격리와 상세 진단 로그 추가
- [x] Flutter 전역 예외 로그에 stack trace 를 함께 남기도록 조정해 재현 시 원인 추적 가능성 강화
- [x] 일정 화면 구장별 보기에서 팀별 필터 칩을 추가해 특정 팀 경기만 구장 기준으로 좁혀볼 수 있게 조정
- [x] 일정 화면 구장별 보기에도 월별 `PageView`를 적용해 좌우 스와이프와 헤더 좌우 버튼으로 달 이동이 가능하도록 정리
- [x] 박스스코어 투수 카드도 타자와 동일한 선수 이미지 매핑을 사용하도록 수정해 프로필 사진이 표시되게 조정

---

## 2026-04-01

### 작업 내용
- [x] GitHub Actions 수동 빌드 워크플로우 `.github/workflows/app-build-artifacts.yml` 추가
- [x] `platform` (`android` / `ios` / `web` / `all`) 과 `app_environment` (`local` / `dev` / `release` / `all`) 입력으로 빌드 매트릭스를 선택할 수 있게 구성
- [x] Android 에서 환경별 `apk`, `aab` 아티팩트를 업로드하도록 구성
- [x] iOS 에서 환경별 unsigned simulator 앱 zip 아티팩트를 업로드하도록 구성
- [x] iOS 인증서/프로비저닝 시크릿이 준비된 경우 선택적으로 signed `ipa` 를 생성하도록 구성
- [x] Web 에서 환경별 정적 빌드 zip 아티팩트를 업로드하도록 구성
- [x] README / 배포 가이드 / Android 서명 가이드 / iOS TestFlight 체크리스트에 GitHub Actions 빌드본 추출 절차와 CI 시크릿 목록 반영
- [x] 남은 GitHub Secrets 등록 / 실행 검증 항목을 `docs/GITHUB_ACTIONS_BUILD_TODO.md` 로 분리 정리

### 검증 메모
- GitHub Actions 워크플로우는 `workflow_dispatch` 수동 실행 기준으로 설계함
- Android 서명 시크릿이 없으면 현재 Gradle 정책대로 debug signing fallback release 빌드가 생성되도록 유지
- iOS 는 기본 경로를 simulator용 unsigned 빌드로 두고, 인증서/프로비저닝 시크릿이 있을 때만 signed `ipa` 경로를 활성화함
- 앱 환경값은 기존 `AppConfig` 의 `APP_ENV=local|dev|release` 정의를 그대로 사용함

### 후속 확인 필요
- [ ] GitHub 저장소 Secrets 에 Android/iOS signing 값을 실제 등록한 뒤 `Actions > App Build Artifacts` 실런 검증
- [ ] signed iOS `ipa` 생성 시 현재 프로비저닝 프로파일 specifier 명이 Runner / Widget 번들 ID와 정확히 일치하는지 확인

---

## 2026-05-18

### 작업 내용
- [x] 현재 기획/디자인 문서 기준으로 제품 보강 방향 감사 문서 작성
- [x] 마이팀 데일리 루프, 홈 브리프, 라이트팬/코어팬 정보 깊이, 알림 프리셋, 위젯 방향 정리
- [x] UI/UX 관점에서 홈, 경기 상세, 일정, 순위, 기록실, 설정/알림별 보강 체크리스트 정리
- [x] 디자인 시스템 관점에서 상태 색상, 카드 체계, 팀 컬러 사용 원칙, 타이포그래피, 이미지 fallback 방향 정리

### 산출물
- `docs/PRODUCT_DESIGN_GROWTH_AUDIT_2026-05-18.md`

### 검증 메모
- 기준 문서: `CLAUDE.md`, `docs/PLANNING.md`, `docs/APP_SPEC.md`, `docs/FIGMA_PROMPT.md`, `docs/UX_AUDIT_2026-03-31.md`, `docs/WORKLOG.md`
- 이번 작업은 기획/디자인 문서화 범위이며, 앱 런타임 화면 캡처나 코드 변경은 수행하지 않음

---

## 2026-05-19

### 작업 내용
- [x] 앱 전역 라우팅 모션 추가: 부트/온보딩 fade, 하단 5탭 fade+미세 slide, 경기 상세/진단 drill-in 전환 적용
- [x] 하단 탭 선택 상태의 아이콘 scale, 배경/테두리, 라벨 스타일 전환을 같은 easing으로 정리
- [x] 화면 전환 모션 원칙을 `docs/APP_SPEC.md`와 `CHANGELOG.md`에 반영
- [x] `docs/PRODUCT_DESIGN_GROWTH_AUDIT_2026-05-18.md`의 제품/디자인 보강안을 기준 문서에 반영
- [x] `docs/PLANNING.md`에 제품 한 줄 정의, 마이팀 데일리 사용 루프, 정보 깊이 원칙, 상태 중심 디자인 원칙 반영
- [x] `docs/APP_SPEC.md`에 홈 마이팀 브리프 상태별 규칙, 경기 상세 탭 간 맥락 연결, 일정/순위 보강, 알림 프리셋, 위젯 원칙 반영
- [x] `docs/FIGMA_PROMPT.md`에 5탭 구조, 기록실 페이지, 카드 체계, 상태 표현, 알림 프리셋 UI, 홈 상태 프레임 보강 반영
- [x] 모바일 디자인 보드 HTML 제작 (`docs/design/kbo-fans-mobile-ui-2026-05-19/index.html`)
- [x] 디자인 보드 렌더 확인용 preview 이미지 생성 (`docs/design/kbo-fans-mobile-ui-2026-05-19/preview.png`)
- [x] UI/UX 원칙과 플랫폼 레퍼런스를 반영한 v2 방향 문서 작성 (`docs/UI_UX_REFERENCE_DEVELOPMENT_2026-05-19.md`)
- [x] 레퍼런스 기반 v2 모바일 디자인 보드 제작 (`docs/design/kbo-fans-mobile-ui-reference-v2-2026-05-19/index.html`)
- [x] v2 디자인 보드 렌더 확인용 preview 이미지 생성 (`docs/design/kbo-fans-mobile-ui-reference-v2-2026-05-19/preview.png`)
- [x] 디자인 철학 / 플랫폼 UX / 스포츠앱 레퍼런스 기반 v3 방향 문서 작성 (`docs/UI_UX_DESIGN_PHILOSOPHY_REFERENCE_2026-05-19.md`)
- [x] `Stadium Control Room for My Team` 콘셉트의 v3 모바일 디자인 보드 제작 (`docs/design/kbo-fans-mobile-ui-philosophy-v3-2026-05-19/index.html`)
- [x] v3 디자인 보드 렌더 확인용 preview 이미지 생성 (`docs/design/kbo-fans-mobile-ui-philosophy-v3-2026-05-19/preview.png`)
- [x] 알림 강도 / 앱 밖 경험 v3 문제를 기준으로 notification, Live Activity, Android Live Update, Widget 트렌드 재분석 문서 작성 (`docs/UI_UX_NOTIFICATION_OUTSIDE_APP_TRENDS_2026-05-19.md`)
- [x] `Moment Subscription & Surface Strategy` 콘셉트의 v4 모바일 디자인 보드 제작 (`docs/design/kbo-fans-mobile-ui-alerts-outside-v4-2026-05-19/index.html`)
- [x] v4 디자인 보드 렌더 확인용 preview 이미지 생성 (`docs/design/kbo-fans-mobile-ui-alerts-outside-v4-2026-05-19/preview.png`)
- [x] 실제 마케팅/발표자료 제작을 가정한 5장 Feature Graphics 구성과 Claude Design PPT 프롬프트 작성 (`docs/FEATURE_GRAPHICS_CLAUDE_DESIGN_PROMPT_2026-05-19.md`)
- [x] KBO Fans 5장 Feature Graphics HTML 시안 제작 (`docs/design/kbo-fans-feature-graphics-2026-05-19/index.html`)
- [x] Feature Graphics 전체 preview 및 개별 slide PNG 5장 생성 (`docs/design/kbo-fans-feature-graphics-2026-05-19/preview.png`, `slide-01.png` ~ `slide-05.png`)
- [x] Feature Graphics 메시지를 마이팀 한눈 보기, 경기 일정/예매/예매 알림, 득점/역전 알림, 실시간 문자중계, 선수 기록실 기준으로 재구성
- [x] Claude Design PPT 프롬프트와 HTML/PNG 시안을 동일한 5대 차별점 기준으로 갱신
- [x] v4 알림 / 앱 밖 경험 기준을 `docs/APP_SPEC.md`, `docs/FIGMA_PROMPT.md`, `docs/PLANNING.md`의 canonical 제품/화면/API 계약에 반영
- [x] 구형 `알림 프리셋 + 이벤트 토글 + 실시간 위젯` 표현을 `Moment Subscription + Surface 분리 + Widget Status Board` 기준으로 재정의
- [x] KBO 데이터 갱신 구조 P0 구현: 기본 direct scrape/fallback 제거, startup/detail preload 축소, Schedule/Home 자동 detail preload 제거, Score/Relay/Lineup 탭 과다 provider 의존 축소
- [x] `docs/KBO_DATA_REFRESH_ARCHITECTURE_2026-05-19.md`에 P0 구현 상태와 남은 P1 범위 기록
- [x] KBO 데이터 갱신 구조 P1 일부 구현: backend `SingleFlight` 추가, 동일 날짜 scoreboard 병렬 요청 병합, `/game/{gameId}` 단건 상세가 같은 날짜 전체 경기 enrich를 수행하지 않도록 변경
- [x] `/api/game/{gameId}`가 scoreboard/game summary 성공 시 schedule fallback 조회를 추가로 하지 않도록 정리

### 검증 메모
- 라우팅 모션 변경은 기존 `NoTransitionPage` 기반 하단 탭을 `CustomTransitionPage` 공통 helper로 바꾼 범위이며, OS 접근성의 애니메이션 줄이기 설정이 켜진 경우 전환 애니메이션을 생략하도록 처리함
- 검증으로 `fvm dart format`, `fvm flutter analyze`, 기존 Flutter 테스트 3종, `fvm flutter build web --release`, `http://localhost:7357` Puppeteer smoke를 실행했고 하단 5탭과 경기 상세 hash 라우팅 렌더를 확인함
- `kbo-doc-sync` 기준으로 UX/화면 상태 변경은 `APP_SPEC`와 `WORKLOG`에 반영
- 해당 v4 디자인 보드 작업 시점에는 실제 앱 UI 구현이나 Figma MCP 작업은 수행하지 않았고, 이후 앱 코드 반영은 같은 날짜 상단 작업 이력과 `CHANGELOG.md`에 따로 기록함
- Figma MCP 제작 도구는 현재 세션에서 호출 가능한 형태로 노출되지 않아, 우선 저장소 내 HTML 디자인 보드로 제작
- Playwright CLI + system Chrome channel 로 HTML 디자인 보드 full-page screenshot 생성 확인
- v2 UI/UX 보강은 Android NavigationBar/Layout 가이드, NN/g usability heuristics, WebAIM WCAG target size, Apple Widget/Live Activity 문서를 참고해 홈/상세/일정/기록실/알림/위젯 화면에 반영
- v2 디자인 보드는 외부 이미지 의존 없이 CSS 기반 팀 배지와 UI 요소로 렌더 안정성을 확보하고, Playwright CLI + system Chrome channel 로 full-page screenshot 생성 확인
- v3 UI/UX 보강은 GOV.UK Service Design, Calm Technology, Apple HIG/Widgets/Live Activities, Material 3, Microsoft Inclusive Design, IBM Design Language, Atomic Design, Baymard mobile app UX, ESPN/theScore 스포츠앱 패턴을 참고해 `Now / Next / Later`, `Attention Dial`, `Field View`, `Small Scoreboard Widget`, 반복 가능한 상태 컴포넌트 체계로 재정리
- v3 디자인 보드는 외부 이미지 의존 없이 CSS 기반으로 제작했고, Playwright CLI + system Chrome channel 로 full-page screenshot 생성 확인
- v4 UI/UX 보강은 Apple notification summary / Live Activities / Widgets, Android notification runtime permission / Live Updates, theScore Live Activities & Events, ESPN alert preferences를 참고해 `알림 강도`를 `Moment Subscription`, `앱 밖 경험`을 iOS Live Activity / Android Live Update / Widget / Push 역할 분리로 재설계
- v4 디자인 보드는 외부 이미지 의존 없이 CSS 기반으로 제작했고, Playwright CLI + system Chrome channel 로 full-page screenshot 생성 확인
- Feature Graphics는 Google Play Feature Graphic 공식 요구사항인 1024x500 변환 가능성을 고려하되, Claude Design / PPT 사용성을 위해 16:9 wide layout으로 제작. 전체 preview와 각 slide 단위 PNG를 Playwright CLI + system Chrome channel 로 생성 확인
- 사장님이 지정한 핵심 매력 요소인 마이팀, 일정/예매, 예매 알림, 득점/역전 알림, 실시간 중계, 선수 기록실을 5장 Feature Graphics 구성과 개별 PNG에 재반영하고 Playwright CLI + system Chrome channel 로 재렌더 확인
- v4 canonical 반영은 당시 문서/spec/API 계약 범위였으며, 이후 Flutter 앱 반영은 같은 날짜 상단 작업으로 이어서 기록함
- 디자인 보드 변경 자체는 문서/디자인 산출물 범위였고, 별도 앱 런타임 캡처는 수행하지 않음
- KBO 데이터 갱신 P0 구현 검증으로 `fvm dart format`, `fvm flutter analyze`, `fvm flutter test test/widget_test.dart test/data/models/records_overview_test.dart test/services/push_notification_service_test.dart` 실행, 모두 통과
- KBO 데이터 갱신 P1 backend 검증으로 `backend/.venv/bin/python -m compileall backend/src`, `backend/.venv/bin/pytest -q backend/tests/test_scoreboard_service_cache.py backend/tests/test_games.py backend/tests/test_snapshot_services.py`, `backend/.venv/bin/pytest -q` 실행, 전체 41개 테스트 통과
