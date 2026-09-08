# KBO Fans 기능·기획 전수 점검

기준일: 2026-09-07. 작업 기준 커밋: `27bcbaedaf9791a276a23c91115a4901c66b8733`와 이번 리뉴얼 작업의 변경 소스. 이 문서는 전체 제품 영역의 현재 구현, 기획과의 차이, 이번 변경의 범위를 정리한다. 최종 빌드·실행·배포 상태는 [리뉴얼 작업 보고서](RENEWAL_2026-09-07.md)를 함께 확인한다.

## 1. 요청과 제품 방향

사장님의 최초 요청은 앱의 기능과 구현 기획을 세세하게 돌아보고, 디자인을 포함해 기능을 리뉴얼하여 시장의 다른 앱과 차별화하는 것이었다. 이후 우선순위는 다음 두 가지를 함께 충족하는 것으로 확정했다.

1. **내 팀의 경기를 빠르게 확인한다.** 실행 후 오늘의 경기 여부, 상대, 점수, 상태와 바로 할 행동을 먼저 보여준다.
2. **깊이 있는 기록 분석과 야구 이해를 돕는다.** 궁금한 숫자의 의미를 현재 화면에서 이해하고, 같은 조건의 선수 기록을 비교하며 경기 맥락으로 돌아갈 수 있게 한다.

기존 앱에는 스코어보드와 문자중계뿐 아니라 팀·선수 기록실, 시즌별 리더보드, 구장·매치업 일정, 데이터 브리핑, 알림함, 예매 알림, 위젯·Live Activity 서비스까지 존재한다. 따라서 이번 작업은 기존 기능을 모두 새로 만드는 작업이 아니다. 기능을 전수 점검한 뒤 핵심 정보의 순서, 탐색 연결, 설명과 비교, 데이터 상태의 진실성을 실제 코드에서 개선한다.

차별화 가설은 **빠른 경기 확인 → 경기 이해 → 기록 탐색·비교 → 다음 경기 준비**의 연결이다. 이 연결이 경쟁 제품보다 더 좋다는 결론은 아직 사용자 비교 실험이나 시장 성과로 검증되지 않았다. 기능 수, 화면 이미지, 자동 테스트 통과만으로 시장 우위를 주장하지 않는다.

## 2. 판단 기준과 근거

| 기준 | 확인한 자료 | 적용 방식 |
|---|---|---|
| 현재 제품 의도 | [AGENTS.md](../AGENTS.md), 사장님의 이번 우선순위 | 마이팀 우선, Flutter+FastAPI, 명시적 API 모드, 데이터 사실성 유지 |
| 화면·API 계약 | [APP_SPEC.md](APP_SPEC.md) | 각 화면 상태, provider, API, 과거/현재 데이터 경계를 대조 |
| 제품 범위와 반복 사용 | [PLANNING.md](PLANNING.md) | 시간대별 사용자 질문과 Phase 1~3 기획을 대조 |
| 디자인 체계 | [FIGMA_PROMPT.md](FIGMA_PROMPT.md) | 다크 스포츠 앱, Jua, 팀 색상, 반응형·접근성 규칙 보존 |
| 현재 동작 | `app/lib/`, `backend/src/`, 대응 테스트 | 문서의 과거 완료 문구보다 현재 소스의 producer→consumer를 우선 |
| 변경 전 화면 | 이번 작업의 `artifacts/renewal-2026-09-07/before/` | 현재 실행에서 확보한 기준 화면. 과거 감사 이미지와 구분 |
| 과거 감사 | `docs/UX_*`, `docs/PRODUCT_DESIGN_GROWTH_AUDIT_*`, 기존 `artifacts/ux-*` | 과거 위험과 선택을 이해하는 맥락. 이번 런타임 통과로 재사용하지 않음 |

`PLANNING.md`의 예전 경쟁표에는 광고·지연 시간·앱 품질 등의 단정과 숫자가 있다. 이 문구는 현재 시장 검증 자료로 취급하지 않는다. 경쟁 비교는 이번 작업에서 확인한 공식 기능 자료와 관찰 범위를 기준으로 [리뉴얼 작업 보고서](RENEWAL_2026-09-07.md)에 별도 정리한다.

## 3. 전체 정보 구조와 데이터 연결

모바일은 `홈 / 일정 / 기록 / 브리핑 / 설정`의 5개 목적지를 유지한다. 순위와 선수 기록은 모바일의 기록 영역에서 전환한다. 700px 이상은 순위를 독립한 6개 NavigationRail 목적지를 사용하고, 1000px 이상에서 라벨을 확장한다. 상세 화면은 게임, 팀 기록, 선수, 리더보드, 알림함, 업데이트 소식, API 진단으로 연결된다.

근거: [app_router.dart](../app/lib/core/router/app_router.dart), [main_scaffold.dart](../app/lib/core/widgets/main_scaffold.dart), [providers.dart](../app/lib/data/providers.dart).

| 제품 영역 | 화면 consumer | provider / service | API 또는 저장 owner |
|---|---|---|---|
| 오늘 경기 | `HomeScreen` | `scoreboardProvider(date)` | `ApiGameRepository` → 경량 `/scoreboard/home` |
| 마이팀 브리프·브리핑 | `HomeScreen`, `NewsScreen` | `homeAggregateProvider(date|team)` | `ApiHomeRepository` → `/home` → `HomeService` |
| 경기 상세 | `GameDetailScreen` | `gameProvider(gameId)` | `ApiGameRepository` → `/game/{gameId}` |
| 문자중계 | `RelayTab` | `relayDataProvider(gameId)` | `/game/{gameId}/relay` → relay service / KBO 로그인 경로 |
| 박스스코어 | `BoxscoreTab` | `gameBoxscoreProvider(gameId)` | `/game/{gameId}/boxscore` → 공식/live context/미제공 구분 |
| 라인업 | `LineupTab` | `gameLineupProvider(gameId)` | `/game/{gameId}/lineup` |
| 일정·매치업 | `ScheduleScreen` | `scheduleProvider(month)`, `seasonScheduleProvider(season)` | 월 일정 API. 시즌 조회는 bounded 월 단위 fan-out |
| 순위 | `StandingsScreen` | `standingsProvider(season)` | `/standings` |
| 기록실 요약 | `RecordsScreen` | `recordsOverviewProvider(season)` | `ApiPlayerRepository` → records overview |
| 팀 선수·팀 기록 | `RecordsScreen(teamId)` | `teamRecordsProvider(team|season)` | 선수와 팀 통계 합본 API |
| 선수·리더보드 | `PlayerDetailScreen`, `LeaderboardScreen` | `playerDetailProvider`, `leaderboardProvider` | 동일 시즌의 player / leaderboard API |
| 마이팀 설정 | `OnboardingScreen`, `SettingsScreen` | `myTeamProvider` | 로컬 설정 저장 후 push registration 수렴 |
| 알림 설정·알림함 | 설정 / 알림함 화면 | `PushNotificationService`, `NotificationInboxService` | 단말 설정·받은 알림 저장, `/push/register` |
| 앱 밖 경기 | 위젯 / Live Activity / Android 진행형 알림 | `WidgetSyncService`, `LiveActivityService` | 단말 native surface + backend scheduler / FCM / APNs |

직접 KBO 파서는 API 모드 실패를 숨기는 자동 대체 경로가 아니다. 명시적 parser/debug 모드로 유지한다. 아래 개선은 이 구분을 바꾸지 않는다.

## 4. 화면별 구현·기획 대조

### 4.1 공통 디자인·탐색

**현재 구현:** 공통 색상·폰트·라이트/다크/OS 고대비·읽을 수 있는 팀 색상 helper, 반응형 content frame, 하단 탐색/rail, 모션 감소, 선택·버튼 semantics가 있다. 근거: [app_theme.dart](../app/lib/core/theme/app_theme.dart), [app_page_frame.dart](../app/lib/core/widgets/app_page_frame.dart), [app_motion.dart](../app/lib/core/widgets/app_motion.dart).

**기획과의 차이:** 실시간 상태를 위한 빨강이 탐색 선택과 일반 primary action에도 넓게 사용되어 상태의 의미가 흐려졌다. 화면별 헤더·카드의 크기와 설명 방식도 누적 변경에 따라 달라져 있었다.

**이번 변경:** 일반 primary·탐색 선택은 액션 accent로 정리하고 선택 배경을 추가했다. 일정 아이콘을 캘린더로 바꾸고 공통 sheet의 모양을 정리했다. 온보딩·홈·기록·브리핑의 정보 위계를 함께 개선했다.

**보존 이유:** 기존 IA, Jua, 밝기/고대비, 모션 감소, 팀 색상은 기존 사용자와 접근성의 기반이다. 리뉴얼을 위해 탭 목적지나 데이터 계약을 불필요하게 바꾸지 않는다.

**후속 검증:** 390×844 변경 후 캡처, 280/320px와 큰 글자, 700/1000px rail, VoiceOver/TalkBack 실제 조작. 위젯 테스트가 native 보조기술 검증을 대신하지 않는다.

### 4.2 온보딩·마이팀 변경

**현재 구현:** 10개 팀 선택, 선택 미리보기, 건너뛰기, 기존 마이팀 변경, 저장 중 상태와 실패 복구, 원래 deep link 복귀가 있다. 팀 저장은 `MyTeamNotifier.setTeam`과 등록 수렴 경로를 사용한다. 근거: [onboarding_screen.dart](../app/lib/features/onboarding/onboarding_screen.dart), [onboarding_state.dart](../app/lib/core/router/onboarding_state.dart), `providers.dart`.

**기획과의 차이:** 첫 화면의 브랜드·미리보기 설명 비중이 높았고, 경기와 기록을 먼저 보여준다는 핵심 가치가 선택 행동보다 분산되어 있었다. 큰 글자에서 고정 카드 높이·말줄임을 다시 점검할 필요가 있었다.

**이번 변경:** `응원팀을 고르면 경기에서 기록까지`의 짧은 목적, 오늘 경기/다음 일정/팀 기록 미리보기, 선택 팀 색상 CTA로 정리했다. 큰 글자는 카드 높이와 줄바꿈으로 대응한다.

**보존 이유:** 마이팀 선택을 강제하거나 알림 권한 요청을 첫 선택과 묶지 않는다. 저장·건너뛰기·편집·deep link 계약을 유지한다.

**후속 검증:** 10팀별 라이트/다크 색 대비, 저장 실패, 첫 실행/편집 모드, 좁은 화면 큰 글자. 실제 알림 등록 수렴은 별도 네트워크·기기 검증 대상이다.

### 4.3 홈·오늘 경기

**현재 구현:** 오늘 scoreboard를 우선 받고, 첫 scoreboard 프레임 이후 집계·팀 기록을 불러온다. 마이팀 브리프, LIVE 마이팀 카드, 전체 경기와 조건부 어제 결과, 순위, 최근 5경기, 인사이트와 빠른 정보가 있다. 근거: [home_screen.dart](../app/lib/features/home/home_screen.dart)의 `_buildContent`, `scoreboardProvider`, `homeAggregateProvider`.

**기획과의 차이:** 기존 홈은 마이팀 통계 브리프가 경기 카드보다 먼저 배치되어 `지금 몇 대 몇인가`라는 질문보다 시즌 정보가 먼저 나타났다. `경기 일정`이라고 표시한 일부 CTA가 오늘 경기 상세를 여는 문제도 있었다. 웹에는 실제 현재 시각과 무관한 `9:41` 장식 상태줄이 남아 있었다.

**이번 변경:** LIVE 마이팀 또는 상태별 `GameDayFocusCard`를 먼저, 전체 경기를 그다음, 팀 통계 브리프를 아래에 배치했다. 예정/라인업 공개/종료/취소·중단에 맞는 CTA를 제공한다. 마이팀의 복수 경기는 LIVE→예정→중단→종료→취소 우선으로 선택한다. 실제 KBO 날짜 헤더를 사용하고 가짜 상태줄을 제거했다. 근거: [game_day_focus_card.dart](../app/lib/features/home/widgets/game_day_focus_card.dart).

**보존 이유:** 핵심 scoreboard를 보조 API나 팀 기록 완료까지 기다리게 하면 빠른 진입이라는 목표가 약해진다. 현재 데이터를 과거 snapshot으로 조용히 대체하거나 미확정 점수를 0점으로 만들지 않는다.

**후속 검증:** 마이팀 미선택/휴식일/경기 전/라인업 공개/LIVE/종료/취소/SUSPENDED/점수 미확정/더블헤더. 현재 `HomeService`의 다음 경기 후보는 주로 현재 월 일정이며 이전 월은 최근 경기 보강용이다. 다음 달 경기까지 항상 확보하는 기능은 이번 변경의 보장 범위가 아니다.

### 4.4 경기 상세 공통

**현재 구현:** 경기 단건 identity, 상태별 기본 탭, 4탭/스와이프, 고정 scorebug, 현재 탭 중심 갱신, 따라가기, 예매·하이라이트 연결이 있다. 근거: [game_detail_screen.dart](../app/lib/features/game_detail/game_detail_screen.dart).

**기획과의 차이:** 스코어·중계·기록이 모두 있어도 라이트팬에게 무엇을 다음에 보면 되는지 설명하는 연결이 약했다.

**이번 변경:** 스코어의 `경기 한눈에`에서 기존 탭으로 이동하는 명시적인 연결을 추가했다. 동일 game provider를 사용하며 별도 경기 조회 경로를 만들지 않는다.

**보존 이유:** API 오류/미제공 상태, 게임 identity, current/historical cache, 탭별 lazy load와 기존 refresh coordinator를 유지한다.

**후속 검증:** 홈/일정/알림/URL deep link 진입, 뒤로·스와이프 복귀, 앱 pause/resume, 경기 상태 변화, 탭 이동 중 요청 실패. 화면 캡처만으로 이 lifecycle을 통과했다고 하지 않는다.

### 4.5 스코어·경기 이해

**현재 구현:** 이닝별 표, R/H/E/B 범례, 현재 이닝 강조, 고정 팀 열, 가로 스크롤, 상태별 미제공 안내가 있다. 근거: [score_tab.dart](../app/lib/features/game_detail/tabs/score_tab.dart).

**이번 변경:** [game_reading_card.dart](../app/lib/features/game_detail/widgets/game_reading_card.dart)에서 현재 제공된 점수로 경기 상태를 설명하고, 검증된 이닝 누적 기록으로 득점 흐름을 보여준다. 예정 경기는 선발·라인업, 진행/종료 경기는 문자중계와 박스스코어로 이어진다.

**사실성 경계:** 이닝 prefix에 중간 누락·음수·총점 불일치가 있으면 득점 서사를 생성하지 않는다. 이닝 누적 점수는 타석별 발생 순서가 아니며, 진행 중 이닝 수치는 바뀔 수 있음을 구분한다. 불완전 기록에서 가상의 결정적 장면·승리 원인을 만들지 않는다.

**후속 검증:** 0:0 LIVE와 최종 무승부, 연장전, 홈 마지막 공격 생략, 기록 정정, 이닝 길이 차이, 총점 미확정, 현재 이닝 갱신. 누적 표 검증과 실제 중계 발생 순서 검증은 별도다.

### 4.6 문자중계

**현재 구현:** 현재 타석·타자/투수·사진, 볼/스트라이크/아웃, 주자 다이어그램, 직전 플레이·교체, 이닝 이동, 새 중계 배너, 득점/교체/종료 강조와 필터, stale/summary 안내가 있다. 근거: [relay_tab.dart](../app/lib/features/game_detail/tabs/relay_tab.dart), `relayDataProvider`.

**이번 변경:** 기존 전체·득점·안타·홈런 등의 필터에 `핵심 장면`을 추가했다. 득점/RUNS/홈런/교체/종료로 분류된 기존 중계 항목을 모으므로 새로운 경기 사건을 추정하지 않는다.

**보존 이유:** 투구별 원문과 전체 필터는 코어팬에게 필요하다. 핵심 장면 선택이 원본 중계를 삭제하거나 서버 응답 순서를 바꾸지 않는다.

**후속 검증:** 새 중계 도착 중 필터·이닝 선택, 공식 feed와 summary fallback의 구분, 주자·카운트 접근성, login/session 갱신, 실시간 실제 경기. 요약 필터가 경기 지연 개선이나 더 빠른 원천을 뜻하지 않는다.

### 4.7 박스스코어

**현재 구현:** 팀 선택, 공식 기록/live context/공식 미제공 상태, 요약·팀 비교·핵심 선수, 타자·투수 기록, 선수 상세 연결이 있다. 공식 수치와 실시간 이름·맥락만 있는 row를 분리한다. 사진 보강은 선택팀의 시즌 선수 데이터에 연결한다. 근거: [boxscore_tab.dart](../app/lib/features/game_detail/tabs/boxscore_tab.dart), `gameBoxscoreProvider`.

**이번 변경:** 경기 한눈에에서 기록 화면으로 가는 진입을 보강했다. 실제 화면에서 확인한 동률/미제공 비교 오류는 표시 직전 원본 완전성 검증으로 수정했다. 확인된 0:0은 `같음`, 장타 일부 필드 미제공은 `–/비교 대기`이며 투수만 있는 팀의 타격 소계를 0으로 만들지 않는다. 제목을 `팀 기록 요약/주요 선수`로 나누고 모바일 선수명·앱 지수의 세로 배치로 잘림을 해소했다. API 파서·공유 계산모델은 유지했다.

**보존 이유:** 이미 진행 중인 current cache·공식 데이터 검증 경로를 디자인 작업으로 무너뜨리지 않는다. 전날 경기의 선수 row를 현재 경기로 빌리는 방식은 허용하지 않는다.

**후속 확장:** 경기 내 기록 비교와 시즌 기준의 차이를 함께 보여줄 수 있으나, 같은 선수·시즌·경기 identity 및 공식 제공 여부를 먼저 확립해야 한다. 현 작업의 2인 비교는 팀 시즌 기록실 기능이다.

### 4.8 라인업·선발 비교

**현재 구현:** 양 팀 선발·타순·교체·불펜, 최근 팀 흐름과 팀 기록 비교, 선발 맞대결이 있다. 공식 boxscore와 팀 선수 데이터가 있을 때만 보강한다. 근거: [lineup_tab.dart](../app/lib/features/game_detail/tabs/lineup_tab.dart).

**이번 변경:** 기존 표출과 데이터 구분을 보존하고, 홈의 공개된 라인업 CTA와 경기 한눈에의 선발·라인업 연결을 추가했다.

**기획 gap:** 타자 대 투수의 직접 상대전적이나 투구 궤적은 현재 라인업 비교와 다른 기능이다. 현재 팀·선발 수치를 그런 데이터처럼 설명하지 않는다.

**후속 검증:** 미발표→발표, 경기 전 교체, 진행 중 교체, 이미지 미제공, 큰 글자, stale 표시·수동 재조회, 실제 기기에서 양 팀 레이아웃.

### 4.9 경기 일정·구장·매치업

**현재 구현:** 월간·주간 캘린더, 날짜 선택·오늘·월 이동, 전체/마이팀/다른 경기, 구장별·선택팀·두 팀 남은 시즌 매치업, 예매 정보와 경기 상세 진입이 있다. 근거: [schedule_screen.dart](../app/lib/features/schedule/schedule_screen.dart), [schedule_game_card.dart](../app/lib/features/schedule/widgets/schedule_game_card.dart).

**기획과의 차이:** 경기가 없는 날짜에서는 빈 상태에서 다음 행동이 끝났다.

**이번 변경:** 현재 읽어온 월 일정과 팀 필터 안에서 다음 예정 경기를 안내한다. 해당 월에 없으면 다음 달 1일로 이동한다. 취소/종료/LIVE/SUSPENDED를 다음 예정 경기로 추천하지 않는다. 같은 월 내 다음 경기 선택은 새 API fan-out을 만들지 않는다.

**독립 리뷰에서 수정한 문제:** 월말 빈 날짜에서 기존 월 이동 함수를 그대로 사용하면 다음 달에도 같은 일자가 선택되어 월초 경기를 건너뛰었다. 새 빈 상태 CTA는 다음 달 1일부터 탐색하도록 수정하고, 기존 월 화살표의 선택 일자 유지 행동은 보존한다.

**후속 검증:** 월말→다음 달 초, 12월→1월, 28/29/30/31일, 마이팀만/다른 경기, 모든 경기 취소, 비시즌. 안내는 현재 확보한 일정 안의 후보이며, 시즌 전체 다음 경기를 항상 한 번에 가져오는 기능이 아니다.

### 4.10 순위

**현재 구현:** 시즌 선택, 팀 순위·승패무·승률·게임차·연속 결과·최근 성적, 마이팀 강조, 모바일 기록실 전환, 명시적인 로딩/오류/재시도가 있다. 근거: [standings_screen.dart](../app/lib/features/standings/standings_screen.dart), `standingsProvider`.

**이번 변경:** 현재 순위 계산·화면을 유지하고 공통 탐색/색상 및 홈·브리핑의 연결을 정리했다.

**보존 이유:** 검증된 시즌별 순위를 임의의 승률 추정·가짜 최근 경기·현재 시즌 snapshot fallback으로 바꾸지 않는다.

**후속 확장:** 일정 강도, 순위 변동 그래프, 경우의 수는 유용할 수 있으나 과거 일별 snapshot과 계산 범위가 필요하다. 이번 상태 표시는 포스트시즌 확률 모델이 아니다.

### 4.11 기록실·팀 선택

**현재 구현:** 시즌 선택, 대표 타자·투수, 지표별 리더·리더보드 preview, 팀 검색, 마이팀 우선 10팀, 팀별 기록 진입이 있다. 검색은 팀 이름 검색이며 전체 선수 통합 검색이 아니다. 근거: [records_screen.dart](../app/lib/features/records/records_screen.dart), `recordsOverviewProvider`.

**기획과의 차이:** 과거 시즌을 고른 뒤 팀 카드로 이동할 때 시즌 query를 전달하지 않아 현재 시즌으로 돌아갔다. 지표명·짧은 카피는 있으나 정의·계산·같이 볼 수치를 여는 기능은 없었다.

**이번 변경:** 팀 진입과 복귀에서 시즌을 보존하고, 같은 route의 팀/시즌 변경도 화면 상태에 반영한다. 헤더를 탐색 목적 중심으로 정리하고 지표별 이해 경로를 넣었다. TOP 5 preview의 실제 표시도 5명으로 맞췄다. `initialSeason`과 `followsCurrentSeason`을 라우터에서 전달한다.

실제 화면 점검에서 리그 overview가 늦게 도착하면 팀 목록이 아래로 밀려 마이팀·선수 비교 진입이 묻히는 문제가 확인됐다. 시즌·기록 가이드 바로 아래에 **내 팀 선수 기록·비교 바로가기**를 overview의 로딩/오류/완료 상태와 독립적으로 배치했다. 일반 팀 목록에서는 중복을 제외하고, 검색 중에는 일치하는 모든 팀을 보여주므로 내 팀도 정상 검색된다. 마이팀 미선택 상태의 팀 검색·목록은 유지한다. 지연 데이터 완료 전후 바로가기의 화면 좌표, 선택 시즌 query, 검색 결과를 회귀 검증하며 API/provider 호출 경로는 바꾸지 않는다.

**후속 검증:** 고정 과거 시즌, 현재 시즌 추적, KST 연도 변경, 주소 직접 진입, 팀 변경, back/pop와 deep link. 이 작업이 순위 화면의 별도 시즌 선택까지 앱 전역으로 동기화하는 것은 아니다.

### 4.12 팀 선수 목록·2인 비교

**현재 구현:** `teamRecordsProvider(team|season)`에서 팀 통계·선수 목록을 함께 받고 야수/투수, 전체/엔트리/엔트리 제외, 이름·주요 지표 정렬로 탐색한다.

**이번 변경:** [player_comparison_sheet.dart](../app/lib/features/records/player_comparison_sheet.dart)에서 현재 필터 안의 같은 팀·같은 시즌·같은 선수군 두 명을 비교한다. 타자는 AVG/OPS, 투수는 ERA/WHIP를 사용한다. 두 명 미만이면 비교를 열지 않는다. 선택 초기화, 같은 선수 중복 선택 방지, 닫기, 큰 글자 세로 배치를 제공한다.

실데이터에서 OPS가 미제공이어도 의미 있는 비교를 할 수 있도록, 양쪽 선수의 `seasonStats`에 명시된 정수 key가 있을 때만 야수 HR, 투수 SO/W/SV 누적값을 추가한다. 같은 key 중복·단위 혼합·자연어 수치는 추정하지 않고 제외한다. 누적값의 차이는 출전 기회와 함께 읽도록 표시한다. 실제 웹에서 발견한 선택 선수명 잘림은 dense dropdown의 텍스트 영역과 메뉴 padding 충돌을 제거하고 기본/큰 글자의 glyph가 실제 그리기 영역 안에 들어가는 회귀로 검증한다.

팀 통계 상단에서는 아래 큰 수치와 반복되던 ERA·WHIP·홈런 보조 문구를 제거했다. OPS는 실제 유효한 값이 있을 때만 타율 아래 보강하여, `OPS -` 같은 빈 정보를 반복하지 않는다.

**사실성 경계:** 이미 받은 typed 수치만 비교한다. `null`, 음수, 비정상 수치는 `–`로 표시하고 차이를 계산하지 않는다. 경기 수/타수/이닝이 원자료에 있으면 같이 표시하고 없으면 표본 미제공으로 남긴다. 차이는 앱 계산값이며, 리그 전체 평균·백분위·공식 순위·종합 실력 점수를 새로 만들지 않는다. sheet의 선택은 닫으면 사라져 다른 시즌·필터로 넘어가지 않는다. 추가 선수 조회 API는 없다.

**후속 확장:** 다른 팀 선수 비교, 다중 시즌 추이, PA/IP 등 표본의 구조화, 대체선수·수비·주루를 포함한 종합 분석은 별도 계약이 필요하다. 원자료가 없는 상태에서 비교 범위만 넓히지 않는다.

### 4.13 리더보드·지표 이해

**현재 구현:** 타자/투수별 지표 전환, 정렬된 순위, 선수 상세, 공식/앱 계산/미지원 배지, OPS 상대지수 disclosure가 있다. WAR는 현재 공식 지원 지표로 취급하지 않는다. 근거: [leaderboard_screen.dart](../app/lib/features/records/leaderboard_screen.dart), [records_overview.dart](../app/lib/data/models/records_overview.dart).

**이번 변경:** 선택 지표 설명 진입, 계산식 맥락, 공통 [baseball_metric_guide.dart](../app/lib/core/widgets/baseball_metric_guide.dart)를 제공한다. 가이드는 AVG, OPS, ERA, WHIP, HR, W, SV, SO, OPS 상대지수의 9개다. 지표마다 정의·계산식·함께 읽을 값을 분리한다.

**보존 이유:** `opsPlus` wire key는 기존 데이터 호환을 위해 유지하지만 표시 의미는 포함 선수 OPS 평균을 100으로 놓은 상대지수다. 이를 공식 OPS+나 wRC+로 설명하거나 리그 전체 보정값으로 승격하지 않는다. 공식 용어 출처는 앱 가이드에서 MLB 용어집으로 연결하며, 이 링크가 KBO 경기 데이터 공급자를 뜻하지 않는다.

### 4.14 선수 상세

**현재 구현:** 시즌별 선수 프로필, 사진과 신체/경력 정보, 주요·시즌 기록, 최근 5경기, 노트와 빈 상태, 오류 재시도가 있다. 근거: [player_detail_screen.dart](../app/lib/features/records/player_detail_screen.dart), `playerDetailProvider`.

**이번 변경:** 설명할 수 있는 기록 카드를 누르면 해당 지표 가이드가 열린다. 기록값의 기존 접근성 이름은 유지하고 도움말 action/hint를 추가했다. 헤더 도움말과 카드 위계를 정리했다.

**기획 gap:** 시즌별 프로필을 통산 기록 완성이나 모든 선수의 역사 데이터 검증으로 볼 수 없다. 최근 5경기·노트가 비어 있을 때 임의의 평가를 채우지 않는다.

**후속 검증:** 타자/투수/은퇴 선수, 이미지 실패, 일부 지표 미제공, 과거 시즌과 current rollover, 수치 카드 semantics, 작은 화면 큰 글자.

### 4.15 데이터 브리핑

**현재 구현:** `/home` 데이터를 경기/순위/기록/마이팀으로 정리하고, 먼저 볼 흐름과 상세 카드로 관련 화면에 연결한다. 실제 뉴스 기사가 아니라 앱이 자동 정리한 데이터임을 표시한다. 일부 페이스 값은 앱 계산임과 분모를 밝힌다. 근거: [news_screen.dart](../app/lib/features/news/news_screen.dart).

**기획과의 차이:** 먼저 볼 카드가 본문에 반복되었고 짧은 말줄임 때문에 수치의 근거·조건이 가려질 수 있었다. 목적별 필터를 바꾸어도 공통 lead 영역이 남아 필터의 의미가 흐려졌다.

**이번 변경:** 전체 화면은 서로 다른 목적의 lead를 우선하고 각 항목을 lead 또는 본문에서 한 번씩 표시한다. 목적별 필터는 해당 항목 전체를 보여준다. lead에도 subtitle·근거·행동을 표시하고, 큰 글자와 좁은 화면에서는 설명을 줄바꿈한다. 생성 시각은 날짜와 한국시간을 함께 표시한다.

**사실성 경계:** 중복 제거는 같은 항목 객체를 lead와 본문으로 나누는 작업이다. 서로 다른 기록·동일 선수의 다른 지표를 같은 사실로 합치지 않는다. 브리핑의 설명 카피나 페이스 추정은 기사, 경기 결과 예측, 공식 기록 판정과 구분한다.

**후속 검증:** 한두 개 항목만 있는 응답, 동일 선수의 다른 지표, 필터 빈 상태, 0:0, 순위/기록 오류, 생성 시각 미제공, 마이팀 변경, KST 날짜 변경.

### 4.16 설정·알림 관전 스타일

**현재 구현:** 마이팀 변경, 화면 모드, OS 알림 권한 상태/요청, 경기 전후 4개와 경기 중 6개 이벤트 토글, 알림함, 진단·버전·업데이트·약관·지원이 있다. 근거: [settings_screen.dart](../app/lib/features/settings/settings_screen.dart).

**이번 변경:** `결과 중심 / 주요 순간 / 직접 설정`을 추가했다. 결과 중심은 경기 종료·취소 결과에 해당하는 `gameEnd`, 주요 순간은 라인업/시작/득점/홈런/역전/종료를 선택한다. 직접 설정은 기존 값을 바꾸지 않고 개별 선택으로 이어진다. 권한 요청을 프리셋 선택에 묶지 않는다.

**서버 계약 확인:** 프리셋은 기존 `withMomentEnabled` → `saveSettings` → `deliveryModes` 포함 `/push/register`를 사용한다. [push.py](../backend/src/kbo_fans_backend/services/push.py)의 game-moment topic gate는 `enabled && delivery != off`이므로 기존 summary 종류의 종료·라인업 선택도 수용한다. [push_notification_service.dart](../app/lib/services/push_notification_service.dart)의 등록 동기화와 별개로 실제 수신은 권한·등록·FCM/APNs·worker 상태를 필요로 한다.

**보존 이유:** 기존 상세 토글, `allGames` 등 기존 설정 값, 수신 조건 안내, OS 권한 제어를 유지한다. 새 프리셋이 새로운 서버 알림 종류나 묶음 발송 SLA를 약속하는 것은 아니다.

**후속 검증:** 기존 사용자 설정 migration, 저장 실패, permission denied, 마이팀 미선택, 직접 팔로우 경기, 프리셋→상세 토글, 재실행, 실제 원격 발송과 중복 방지.

### 4.17 알림함·업데이트·지원

**현재 구현:** 알림함은 전체/안 읽음/경기/브리프, 읽음 처리, 저장된 알림의 상세 deep link, 현재 알림 플레이북을 제공한다. 업데이트 소식은 버전별 문서와 읽음 상태, 진단은 현재 API 상태를 다룬다. 근거: [notification_inbox_screen.dart](../app/lib/features/notifications/notification_inbox_screen.dart), [patch_notes_screen.dart](../app/lib/features/settings/patch_notes_screen.dart), [api_diagnostics_screen.dart](../app/lib/features/settings/api_diagnostics_screen.dart).

**이번 변경:** 기존 기능을 보존했다. 홈·설정의 명확한 진입과 새 알림 프리셋을 통해 접근을 연결한다.

**후속 검증:** 잘못된 route, 오래된 알림, 저장 손상/읽기 실패, update-note 새 설치/업데이트 구분, 지원 메일 앱 미설치. 설정 화면의 진단은 데이터 수신 성공 전체를 보장하지 않는다.

### 4.18 예매·하이라이트

**현재 구현:** 예정 경기의 예매처 링크와 공식/예상 오픈 시각, 예매 알림 상태·로컬 예약, 종료 경기 하이라이트 lazy 조회와 인라인/외부 이동이 있다. 근거: `GameDetailScreen`의 `_TicketInfoCard`, `_HighlightSection`, [ticket_alert_service.dart](../app/lib/services/ticket_alert_service.dart), [ticketing_policy.dart](../app/lib/core/constants/ticketing_policy.dart).

**이번 변경:** 기존 링크·예약 경로를 유지했다. 경기 전/다음 일정 탐색과 연결한다.

**기획 gap:** 잔여석 실시간 조회, 실제 좌석 구매, 구장 날씨, 현장 동선은 구현 확인 범위가 아니다. `예상 오픈`을 실제 예매 가능 시각으로 보장하지 않는다. 하이라이트 검색 결과는 공식 경기 영상의 권리·재생 가능성을 보장하지 않는다.

### 4.19 위젯·Live Activity·Android 진행형 알림

**현재 구현:** 단말 위젯 동기화, 선택 경기·마이팀 자동 따라가기, iOS Activity 등록/갱신/종료, backend push-to-start·sync worker, Android 진행형 경기 알림 코드가 존재한다. 근거: [widget_sync_service.dart](../app/lib/services/widget_sync_service.dart), [live_activity_service.dart](../app/lib/services/live_activity_service.dart), [live_activity_scoreboard.py](../backend/src/kbo_fans_backend/services/live_activity_scoreboard.py), `app/ios/`, `app/android/`.

**이번 변경:** native payload·서버 발송·서명 capability를 바꾸지 않았다. 홈에서 마이팀 경기를 먼저 보여주는 UI와 기존 따라가기 경로가 함께 유지된다.

**보존 이유:** 앱을 닫은 뒤의 경험은 웹 렌더링이나 Flutter 카드 변경만으로 개선 완료를 증명할 수 없다. scoreAvailable, SUSPENDED 비종료, installation owner, token lifecycle, 중복 발송 방지 등 별도 계약을 유지한다.

**후속 검증:** 실제 iPhone Dynamic Island/잠금화면, Android 지원 기기, 앱 종료 상태, 네트워크 전환, 권한 거절/철회, 새 경기 교체, 종료·취소·중단, 실제 FCM/APNs delivery/receipt. 현재 task의 앱 테스트 통과와 분리한다.

## 5. 백엔드·로컬 모델 변경의 정확한 범위

[home.py](../backend/src/kbo_fans_backend/services/home.py)와 [home_aggregate.dart](../app/lib/data/models/home_aggregate.dart)의 이번 계약 보강은 다음과 같다.

| 문제 | 변경 | 보존 경계 |
|---|---|---|
| 0:0도 확인된 점수인데 접전 후보에서 빠짐 | 합계가 양수라는 조건 대신 검증된 양 팀 점수로 active 후보 선정 | 미확정/비정상 점수는 후보로 승격하지 않음 |
| 종료 동점 경기를 `1점 승부`로 표현 가능 | 종료 동점은 `무승부`로 분기 | LIVE 접전과 최종 결과의 상태 구분 |
| score unknown에서 오늘 경기 quick item에 수치 노출 가능 | backend는 유효한 비음수 정수 여부, 앱은 score availability 확인 | 없는 점수는 matchup/status로 설명 |
| 경기가 있는데 브리핑 item이 없어 휴식일 fallback 가능 | 경기 정보가 있으면 경기 상태 확인 item | 실제 빈 경기일에만 offday |
| 다음 경기에 이미 끝나거나 취소된 경기 포함 가능 | `SCHEDULED`만 nextGame 후보 | 오늘 경기 identity와 팀 필터 유지 |

파서, 원천 호출 빈도, API envelope, 배포 topology, secret, push outbox, 앱 cache fallback 정책은 이 변경으로 교체하지 않는다. 서비스 fixture 통과는 운영 upstream의 모든 경기 데이터 검증과 다르다.

## 6. 기획상 확장 기능과 현재 완료 범위

| 기획 항목 | 현재 확인 수준 | 다음 결정·검증 |
|---|---|---|
| 시즌별 선수 기록 | 구현됨. source/snapshot 완전성에 따른 빈 상태 존재 | 지원 시즌별 identity와 완성도 검증 |
| 선수 비교 | 이번에 같은 팀·시즌·선수군의 2인 핵심 지표 비교 구현 | 타팀/다중 시즌/표본 구조화는 별도 확장 |
| 통산 기록·시즌 추이 | 현 route에서 완전한 기능으로 확인되지 않음 | 원자료 범위와 과거 snapshot 계약 |
| 기록 달성/시즌 타임라인 | overview/브리핑에 관련 필드·항목이 있으나 완전한 독립 타임라인은 아님 | 달성 검증 기준·이벤트 identity·누락/정정 처리 |
| 팀 상대전적 | 남은 일정의 두 팀 매치업 조회는 있음 | 완료 경기 상대전적·분모·시즌 범위가 별도 |
| 날씨·잔여석·직관 도우미 | 일반 기능 완성으로 확인되지 않음 | 공급 API/비용/사용자 효용을 먼저 확립 |
| 커뮤니티·채팅 | 현재 주요 route에 없음 | 계정·운영·신고/차단·유지비 포함 제품 결정 |
| 예측 게임 | 현재 주요 route에 없음 | 게임 정책·점수/보상·참여의 반복 이유 별도 결정 |
| 퓨처스리그 | 현재 공식 지원 화면으로 확인되지 않음 | 리그 identity·일정/기록 source 계약 |
| 전체 선수 통합 검색 | 현재 팀 검색과 팀별 선수 목록으로 탐색 | 선수 인덱스·동명이인·이적/은퇴 identity 설계 |

위 항목을 무조건 추가해야 더 좋은 앱이 되는 것은 아니다. 두 핵심 가치에 얼마나 도움이 되는지, 현재 원자료로 정직하게 제공할 수 있는지, 운영 가능한지를 기준으로 우선순위를 정한다.

## 7. 변경 전 화면 근거

이번 작업에서 수집한 기준 캡처는 다음 파일이다. 파일의 존재와 화면 범위는 확인했으며, 모든 기능·모든 상태의 런타임 검증을 뜻하지 않는다.

| 화면 | 캡처 |
|---|---|
| 온보딩 | [01-onboarding.png](../artifacts/renewal-2026-09-07/before/01-onboarding.png) |
| 홈 | [02-home.png](../artifacts/renewal-2026-09-07/before/02-home.png) |
| 기록실 | [03-records.png](../artifacts/renewal-2026-09-07/before/03-records.png) |
| 일정 | [04-schedule.png](../artifacts/renewal-2026-09-07/before/04-schedule.png) |
| 브리핑 | [05-briefing.png](../artifacts/renewal-2026-09-07/before/05-briefing.png) |
| 설정 | [06-settings.png](../artifacts/renewal-2026-09-07/before/06-settings.png) |
| 경기 스코어 | [07-game-score.png](../artifacts/renewal-2026-09-07/before/07-game-score.png) |
| 문자중계 | [08-relay.png](../artifacts/renewal-2026-09-07/before/08-relay.png) |

박스스코어, 라인업, native 위젯·Live Activity, 알림 권한 UI, 모든 빈 상태/오류 상태를 위 여덟 장으로 확인했다고 적지 않는다. 변경 후 화면·추가 상태의 증거는 [리뉴얼 작업 보고서](RENEWAL_2026-09-07.md)에 연결한다.

## 8. 검증과 출시 증거의 구분

| 증거 층 | 이번 문서에서 인정하는 것 | 별도 확인이 필요한 것 |
|---|---|---|
| 소스·정적 분석 | producer/consumer, route·시즌·필터·표시 조건 검토 | 실제 데이터·실제 기기에서 같은 결과 발생 |
| Flutter 위젯/단위 테스트 | fixture의 상태 전이·선택·오류·큰 글자·기록값 조건 | 성능 수치·보조기술 실제 조작·실시간 경기 |
| backend 테스트 | HomeService의 검증된 점수·상태·다음 경기 계약 | 운영 KBO crawl·cache·worker 상태 |
| API health | 특정 시점 특정 endpoint의 응답 확인 | 모든 화면 API·freshness·게임 identity·push delivery |
| 로컬 웹/시뮬레이터 | 확인한 route·viewport·상태의 렌더링 | iOS/Android 실제 기기·앱 종료 상태 |
| 서명 artifact | 실제 빌드가 생성되고 서명된 경우 그 artifact | upload·Apple processing·테스터 설치 |
| TestFlight/스토어 | upload, VALID, 그룹 배정, Beta Review를 각각 확인 | 외부 설치 가능과 실제 사용자 경험 |
| 시장/사용자 성과 | 측정한 사용자 연구나 비교 실험 | 더 빠른 앱·최고 앱·재방문 증가라는 일반적 결론 |

기록 영역의 검증 항목은 과거 시즌 진입/복귀, 비교 중 추가 API 요청 없음, 시즌/선수군/팀 정합성, 선택 초기화·닫기, 320px·240% 글자, 미제공 수치, 명시 key의 누적값과 모호한 값 제외, 지연 데이터 전후 바로가기 위치, 선택 텍스트의 glyph 그리기 영역이다. 테스트 항목이 추가되는 도중의 부분 실행 횟수를 최종 검사 결과로 합산하지 않는다. 모든 작업자의 마지막 변경을 포함한 최종 전체 검사 결과는 [리뉴얼 작업 보고서](RENEWAL_2026-09-07.md)를 정본으로 삼는다.

이번 기능 전수 점검은 모든 기획 기능이 새로 구현되었다는 뜻이 아니다. 이번 소스·테스트·캡처로 확인한 개선과, 보존한 기능, 운영/기기 검증, 이후 확장 기능을 각각 구분한다.
