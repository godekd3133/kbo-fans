# KBO Fans 8분 발표 자료

> 목적: 기능별로 **기획한 내용**과 **개발한 내용**만 정리한다.
> 산출물: 실제 앱 화면 중심 PPTX + 발표 원고

## 발표 구성

| 순서 | 슬라이드 | 기획한 내용 | 개발한 내용 |
| --- | --- | --- | --- |
| 1 | KBO Fans | 앱 전체 기능 구성 소개 | 구현된 화면과 준비된 기능 범위 소개 |
| 2 | 마이팀 | 응원팀 선택을 앱 기준값으로 사용 | 온보딩, 설정 변경, 로컬 저장 |
| 3 | 홈 | 오늘 경기와 마이팀 경기 확인 | 홈 화면, 마이팀 카드, 경기 카드 |
| 4 | 경기 상세 스코어 | 한 경기의 점수 흐름 확인 | 상세 스코어 탭, 이닝 스코어 |
| 5 | 문자중계 | 현재 타석과 경기 상황 확인 | 중계 탭, 현재 타석, 카운트 UI |
| 6 | 박스스코어 | 선수별 경기 기록 확인 | 박스스코어 탭, 선수 기록 카드 |
| 7 | 라인업 | 선발 구성과 양 팀 라인업 확인 | 라인업 탭, 팀 비교 화면 |
| 8 | 일정 | 월별 경기 일정 확인 | 일정 화면, 월 이동, 날짜별 경기 카드 |
| 9 | 예매 알림 | 예매 오픈 타이밍 확인 | 예매 알림 service 준비 |
| 10 | 순위 | 팀 순위와 시즌 흐름 확인 | 순위 화면, 팀 순위표 |
| 11 | 기록실 | 선수 기록과 리더보드 확인 | 기록실, 리더보드, 선수 상세 라우트 |
| 12 | 알림 | 장면별 알림 선택 | 알림 설정 UI, 전달 방식 선택 |
| 13 | 데이터 처리 | 현재 경기와 과거 기록 정책 분리 | direct KBO, snapshot, provider routing |
| 14 | 구현 현황 | 현재 구현 범위와 다음 작업 정리 | 화면 구현, service 준비, 기기 검증 과제 |

총 예상 시간: 약 8분

---

## Slide 1. KBO Fans

### 기획한 내용
- KBO 팬이 경기 전, 경기 중, 경기 후에 확인하는 기능을 한 앱에 묶는다.
- 기능은 마이팀, 홈, 경기 상세, 일정, 순위, 기록실, 알림, 데이터 처리로 나눈다.
- 발표에서는 기능별로 기획한 내용과 개발한 내용을 분리해서 설명한다.

### 개발한 내용
- Flutter 앱으로 온보딩, 홈, 경기 상세, 일정, 순위, 기록실, 설정 화면을 구현했다.
- 알림, 예매 알림, 위젯, live activity는 서비스와 정책 단위로 준비했다.
- 실제 앱 캡처를 PPT에 넣어 구현된 화면을 보여준다.

---

## Slide 2. 마이팀

### 기획한 내용
- 사용자가 응원팀을 선택한다.
- 선택한 팀을 홈, 설정, 알림의 기준으로 사용한다.
- 사용자가 나중에 응원팀을 변경할 수 있게 한다.

### 개발한 내용
- `OnboardingScreen`으로 10개 구단 선택 화면을 구현했다.
- `MyTeamNotifier`가 `SharedPreferences`에 선택 팀을 저장한다.
- 설정 화면에서 `/onboarding?mode=edit`로 팀 변경이 가능하다.
- 마이팀 변경 시 push 등록 정보 동기화 흐름을 연결했다.

---

## Slide 3. 홈

### 기획한 내용
- 오늘 경기 정보를 첫 화면에서 확인한다.
- 마이팀 경기와 전체 경기 상태를 함께 확인한다.
- 경기 카드에서 상세 화면으로 진입한다.

### 개발한 내용
- `HomeScreen`을 구현했다.
- `MyTeamGameCard`와 `GameCard`를 구현했다.
- scoreboard provider와 home aggregate provider를 연결했다.
- 하단 탭과 경기 상세 진입 흐름을 구현했다.

---

## Slide 4. 경기 상세 스코어

### 기획한 내용
- 특정 경기의 점수 흐름을 이닝별로 확인한다.
- 팀별 점수, 안타, 실책, 볼넷 같은 합계를 확인한다.
- 하이라이트 영역을 통해 주요 장면을 확인한다.

### 개발한 내용
- `GameDetailScreen`에 스코어 탭을 구현했다.
- `/game/:gameId` 상세 라우트를 연결했다.
- 이닝별 스코어와 팀 합계 UI를 구현했다.
- 하이라이트 영역을 화면에 배치했다.

---

## Slide 5. 문자중계

### 기획한 내용
- 현재 타석을 확인한다.
- 투수, 타자, 볼카운트, 아웃카운트를 확인한다.
- 경기 진행 로그를 확인한다.

### 개발한 내용
- 경기 상세의 문자중계 탭을 구현했다.
- relay provider와 current at-bat provider를 연결했다.
- 현재 타석 카드, 투수/타자 정보, 카운트 UI를 구현했다.
- 중계 리스트를 화면에 표시했다.

---

## Slide 6. 박스스코어

### 기획한 내용
- 선수별 경기 기록을 확인한다.
- 타자 기록과 투수 기록을 구분해서 확인한다.
- 경기 후 어떤 선수가 어떤 기록을 냈는지 확인한다.

### 개발한 내용
- `boxscore_tab.dart`를 구현했다.
- 팀별 박스스코어 전환 UI를 구현했다.
- 선수별 기록 카드와 리스트를 구현했다.
- 경기 상세 탭 안에서 박스스코어를 분리했다.

---

## Slide 7. 라인업

### 기획한 내용
- 양 팀 선발 구성을 확인한다.
- 선발 투수와 주요 타자를 확인한다.
- 경기 전 라인업 정보를 경기 상세 안에서 확인한다.

### 개발한 내용
- `lineup_tab.dart`를 구현했다.
- 팀별 라인업 비교 화면을 구현했다.
- 선발 선수 카드와 팀 비교 UI를 구현했다.
- 경기 상세 탭 안에서 라인업을 분리했다.

---

## Slide 8. 일정

### 기획한 내용
- 월별 경기 일정을 확인한다.
- 날짜별 경기 정보를 확인한다.
- 경기 상태와 구장 정보를 확인한다.

### 개발한 내용
- `ScheduleScreen`을 구현했다.
- `ScheduleGameCard`를 구현했다.
- 월 이동 UI를 구현했다.
- 날짜별 경기 카드와 경기 상태 표시를 구현했다.

---

## Slide 9. 예매 알림

### 기획한 내용
- 예매 오픈 시간을 확인한다.
- 예매 알림을 설정한다.
- 경기 일정과 예매 정보를 연결한다.

### 개발한 내용
- `TicketAlertService`를 구현했다.
- 예매 알림 local reminder 흐름을 준비했다.
- 경기 단위 알림 예약/해제 로직을 구현했다.
- 일정 화면과 연결할 수 있는 service 단위 기능을 준비했다.

---

## Slide 10. 순위

### 기획한 내용
- 팀 순위를 확인한다.
- 시즌 기준 팀 성적을 확인한다.
- 경기 결과가 순위에 반영되는 흐름을 확인한다.

### 개발한 내용
- `StandingsScreen`을 구현했다.
- `/standings` 라우트를 연결했다.
- 팀 순위표 UI를 구현했다.
- 시즌 기준 standings provider를 연결했다.

---

## Slide 11. 기록실

### 기획한 내용
- 선수 기록을 확인한다.
- 주요 지표별 리더보드를 확인한다.
- 리더보드에서 선수 상세로 이동한다.

### 개발한 내용
- `RecordsScreen`을 구현했다.
- `LeaderboardScreen`을 구현했다.
- `PlayerDetailScreen` 라우트를 연결했다.
- `/records`, `/records/leaderboard/:metric`, `/records/player/:playerId`를 구현했다.

---

## Slide 12. 알림

### 기획한 내용
- 경기 시작, 득점, 홈런, 역전, 경기 종료 알림을 구분한다.
- 라인업 공개와 이닝 전환 알림을 구분한다.
- 알림 전달 방식을 선택한다.

### 개발한 내용
- `PushNotificationMoment`를 정의했다.
- `NotificationDeliveryMode`를 정의했다.
- 설정 화면에 알림 목록과 전달 방식 선택 UI를 구현했다.
- `GameEventAlertService`, `LiveActivityService`, `WidgetSyncService`를 준비했다.

---

## Slide 13. 데이터 처리

### 기획한 내용
- 현재 경기 데이터와 과거 기록 데이터를 구분한다.
- 현재 경기는 최신성을 우선한다.
- 과거 기록은 snapshot을 활용한다.
- 앱 밖 화면에서 필요한 경기 데이터를 전달한다.

### 개발한 내용
- no-backend direct KBO 경로를 기본 실행 방향으로 준비했다.
- `gameRepositoryProvider`가 API/direct repository 경로를 선택한다.
- generated asset과 snapshot 경로를 기록실/과거 데이터에 활용한다.
- `WidgetSyncService`와 `LiveActivityService`를 준비했다.

---

## Slide 14. 구현 현황

### 기획한 내용
- 현재 보여줄 수 있는 화면과 다음 검증 대상을 구분한다.
- 앱 화면 구현과 앱 밖 기능 준비 상태를 구분한다.
- 발표에서 과장 없이 현재 범위를 설명한다.

### 개발한 내용
- 화면 구현: 온보딩, 홈, 경기 상세 4탭, 일정, 순위, 기록실, 설정.
- service 준비: 예매 알림, push moment, widget sync, live activity.
- 다음 검증: 실제 기기 push, iOS/Android 위젯, live activity, 테스터 배포.

---

## 구현 근거 요약

| 영역 | 구현 근거 |
| --- | --- |
| 라우팅 | `app/lib/core/router/app_router.dart` |
| 마이팀 저장 | `app/lib/data/providers.dart`의 `MyTeamNotifier` |
| 홈 | `app/lib/features/home/home_screen.dart`, `home/widgets/` |
| 경기 상세 | `app/lib/features/game_detail/game_detail_screen.dart`, `tabs/` |
| 일정 | `app/lib/features/schedule/schedule_screen.dart` |
| 순위 | `app/lib/features/standings/standings_screen.dart` |
| 기록실 | `app/lib/features/records/` |
| 알림 정책 | `app/lib/services/push_notification_service.dart` |
| 예매 알림 | `app/lib/services/ticket_alert_service.dart` |
| 앱 밖 화면 | `app/lib/services/widget_sync_service.dart`, `app/lib/services/live_activity_service.dart` |
| 데이터 정책 | `README.md`, `CHANGELOG.md`, `docs/APP_SPEC.md`, `docs/ENGINEERING_NOTES.md` |
