# KBO Fans 알림 / 앱 밖 경험 v4 재설계

> 작성일: 2026-05-19  
> 범위: 알림 설정, Live Activity, Android Live Updates, 위젯, Lock Screen 진입 경험 재설계  
> 후속 산출물: `docs/design/kbo-fans-mobile-ui-alerts-outside-v4-2026-05-19/index.html`

---

## 1. v3 문제 진단

v3의 `알림 강도`와 `앱 밖 경험`은 방향은 맞았지만 기능 모델이 어색했다.

문제:
- `알림 강도` 다이얼은 사용자가 실제로 이해하는 설정 단위가 아니다.
- 스포츠 알림은 강도보다 `어떤 장면을 받을지`, `바로 받을지`, `요약으로 받을지`, `Live 표면으로 볼지`가 중요하다.
- `앱 밖 경험`이 iOS Live Activity, Android Live Update, Widget, Push Notification의 역할 차이를 충분히 분리하지 못했다.
- Live 표면은 사용자가 특정 경기를 따라가겠다고 명시했을 때 시작되어야 하는데, v3는 자동 노출처럼 보였다.
- 위젯은 실시간 중계판이 아니라 주기적으로 갱신되는 개인화 정보 표면이어야 한다.

v4 결론:

> **알림은 강도 조절이 아니라 Moment Subscription이다.**  
> 사용자는 “내가 구독할 야구 장면”을 고르고, 시스템은 그 장면을 가장 적절한 표면으로 보낸다.

---

## 2. 추가 트렌드 분석

### 2.1 Push Permission은 사용자가 가치를 본 뒤 요청

Android notification permission 문서는 사용자가 앱을 먼저 익히고, 알림 벨을 누르거나 팔로우 같은 명시 행동을 했을 때 권한을 요청하는 흐름을 권장한다.

Apple iPhone User Guide도 알림은 중요 정보만 보도록 사용자 설정을 조정할 수 있고, 요약/Focus/무음 처리 등 사용자가 알림을 통제하는 흐름을 전제로 한다.

KBO Fans 적용:
- 첫 실행에서 바로 권한 요청 금지.
- 홈 경기 카드의 `경기 따라가기` 또는 `득점권 알림`을 탭했을 때 permission sheet를 보여준다.
- 권한 요청 전 `받게 될 알림 예시`를 먼저 보여준다.

### 2.2 알림은 Channel이 아니라 Moment로 설계

스포츠 앱 트렌드는 단순 `ON/OFF`보다 개인화된 favorite, team/player/event 기반 알림이다. ESPN은 팀/판타지별 alert preferences를 제공하고, theScore는 favorite feed와 실시간 scoring alerts를 강조한다.

KBO Fans 적용:
- 알림 설정 단위를 `경기 시작`, `득점`, `역전`, `득점권`, `투수 교체`, `내 선수 타석`, `최종 결과` 같은 Moment로 나눈다.
- Moment마다 전달 방식을 선택한다: `바로 알림`, `요약`, `Live 표면만`, `끄기`.
- 기본값은 사장님 앱 방향에 맞춰 `내 팀 핵심 장면`으로 둔다.

### 2.3 Live Activity / Android Live Update는 “따라가기” 상태

Apple HIG는 Live Activities가 시작과 끝이 분명한 이벤트에 적합하고, 한눈에 필요한 핵심 정보만 보여줘야 한다고 설명한다.

Android Live Updates 문서는 ongoing activity, user-initiated, time-sensitive 조건을 강조한다. 특히 사용자가 스포츠 경기를 모니터링하겠다고 명시하면 Live Update를 시작할 수 있지만, notification에 Unpin action도 포함해야 한다고 설명한다.

KBO Fans 적용:
- `경기 따라가기`를 눌렀을 때만 Live Activity / Android Live Update를 시작한다.
- Live 표면에는 `스코어 / 이닝 / 주자 / BSO / 마지막 업데이트 / 그만 보기`만 둔다.
- 경기 종료 시 자동으로 `최종 결과`로 축소되고, 일정 시간 후 종료한다.
- 단순 앱 빠른 실행, 광고, 예정 경기, 일반 뉴스에는 Live 표면을 쓰지 않는다.

### 2.4 Widget은 실시간 중계가 아니라 “개인화 상태판”

Apple Widget HIG는 위젯을 timely, glanceable content와 focused functionality로 설명하고, 작은 위젯은 한 가지 정보에 집중해야 하며 과밀하면 glanceable하지 않다고 설명한다.

KBO Fans 적용:
- 작은 위젯: `내 팀 다음/현재 경기 상태` 하나만 표시.
- 중간 위젯: `현재 경기 + 다음 경기` 또는 `오늘 내 팀 + 리그 주요 경기`.
- Live 상황에서는 stale 표시 필수.
- pitch-by-pitch는 위젯이 아니라 Live Activity 또는 앱 상세로 보낸다.

### 2.5 앱 밖 표면은 하나가 아니라 4개

| 표면 | 역할 | KBO 적용 |
|------|------|----------|
| Push Notification | 한 번 발생한 중요한 장면 전달 | 득점, 역전, 최종 결과 |
| Notification Summary | 덜 긴급한 장면 묶음 | 경기 전 라인업, 경기 후 기록 |
| Live Activity / Live Update | 사용자가 따라가는 현재 경기 상태 | 내 팀 경기 live follow |
| Widget | 반복적으로 보는 개인화 상태판 | 다음 경기, 현재 스코어, 오늘 요약 |

---

## 3. v4 정보 구조

### 3.1 알림 설정 화면

화면 제목은 `알림 강도`가 아니라 **알림 플레이북**으로 변경한다.

구조:
- 상단: `내 팀 핵심 장면` 기본 프리셋
- 중단: Moment list
- 하단: 전달 방식 요약

Moment 예시:
- 경기 시작
- 선발 / 라인업 발표
- 득점권
- 득점 / 실점
- 역전 / 동점
- 투수 교체
- 내 선수 타석
- 최종 결과

전달 방식:
- 바로 알림
- 요약으로 받기
- Live 표면만
- 끄기

### 3.2 경기 따라가기 화면

`경기 따라가기`는 알림 설정이 아니라 현재 경기 세션 시작이다.

상태:
- 시작 전: `라인업 나오면 알려줘`, `경기 시작 알림`
- 경기 중: `Live Activity 시작`, `득점권 바로 알림`, `그만 보기`
- 경기 후: `최종 결과`, `기록 요약 보기`

### 3.3 앱 밖 경험 화면

v4에서는 iOS/Android/Widget을 같은 화면에 뭉개지 않는다.

보드 구성:
- iOS Lock Screen + Dynamic Island
- Android Live Update + status chip
- Home Screen Widget small/medium
- Push notification stack

---

## 4. v4 디자인 체크리스트

- [x] `알림 강도` 다이얼 제거
- [x] `알림 플레이북`으로 재설계
- [x] Moment별 구독 방식 정의
- [x] 권한 요청 전 알림 예시 노출
- [x] Live Activity / Android Live Update는 user-initiated follow로 제한
- [x] Live 표면에 `그만 보기` 액션 포함
- [x] Widget은 실시간 play-by-play가 아니라 상태판으로 제한
- [x] iOS / Android / Widget / Push 역할 분리

---

## 5. 참고 링크

- Apple Support — View and respond to notifications on iPhone: https://support.apple.com/guide/iphone/view-and-respond-to-notifications-iph6534c01bc/ios
- Apple HIG — Live Activities: https://developer.apple.com/design/human-interface-guidelines/live-activities
- Apple HIG — Widgets: https://developer.apple.com/design/human-interface-guidelines/widgets
- Apple Developer — Displaying live data with Live Activities: https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities
- Android Developers — Notification runtime permission: https://developer.android.com/develop/ui/views/notifications/notification-permission
- Android Developers — Create live update notifications: https://developer.android.com/develop/ui/views/notifications/live-update
- Android Developers — Progress-centric notifications: https://developer.android.com/about/versions/16/features/progress-centric-notifications
- theScore — Live Activities & Events: https://www.thescore.com/news/2885302
- ESPN Support — ESPN App Alerts: https://support.espn.com/hc/en-us/articles/47079227740948-ESPN-Fantasy-App-and-Alerts
