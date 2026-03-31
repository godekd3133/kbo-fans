# 작업 이력 (Work Log)

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

### 확인 사항
- `flutter run -d chrome` 디버그 세션은 정상 렌더링됨
- 별도 `flutter run -d web-server --web-port 7357` 경로는 스플래시에서 멈추는 현상이 있어 웹 배포/프리뷰 경로 추가 점검 필요
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
- [x] 관련 백엔드 회귀 테스트 추가

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

### 문서화
- [x] 홈 전용 aggregate endpoint 기반 성능 개선 제안서 작성 (`docs/PERFORMANCE_PROPOSAL_HOME_AGGREGATE.md`)
- [x] 홈 aggregate endpoint 구현 계획서 작성 (`docs/PERFORMANCE_IMPLEMENTATION_PLAN_HOME_AGGREGATE.md`)
