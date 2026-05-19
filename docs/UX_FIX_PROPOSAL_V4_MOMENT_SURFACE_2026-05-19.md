# V4 Moment Surface UX Fix Proposal

작성일: 2026-05-19  
대상 평가 문서: `docs/UX_REVIEW_V4_MOMENT_SURFACE_2026-05-19.md`  
기준 화면 산출물: `artifacts/kbo-v4-ux-eval/`

## 반영 상태

2026-05-19 현재 P1/P2 주요 앱 화면 수정은 실제 Flutter UI에 반영됐다.

- [x] 알림 전달 용어 copy 정리
- [x] 홈 대표 경기 CTA 상태별 분기
- [x] `MyTeamGameCard` callback 분리
- [x] 경기 상세 하이라이트를 score tab footer로 이동
- [x] 마이팀 브리프 compact / safe area 보강
- [x] 홈/경기상세 상태별 stale copy 보강
- [x] 390x844 web smoke 캡처 갱신
- [ ] iOS Live Activity / Android 홈 위젯 실기기 캡처 QA

## 목적

V4 방향성은 유지한다. 수정의 목적은 디자인을 다시 갈아엎는 것이 아니라, 실제 사용 흐름에서 드러난 불일치를 제거하는 것이다.

핵심 원칙은 4개다.

- 화면은 현재 경기 상태를 숨기지 않는다.
- 버튼 라벨은 누른 뒤 보이는 화면과 일치한다.
- 알림/Live/Widget 용어는 내부 구현명이 아니라 사용자 언어로 쓴다.
- 앱 밖 표면은 플랫폼별 구현 차이와 stale 가능성을 명시한다.

## 수정 우선순위 요약

| 우선순위 | 문제 | 수정 방향 | 기대 효과 |
| --- | --- | --- | --- |
| P1 | 홈 CTA가 하단 탭에 걸림 | safe area + 카드 밀도 재조정 | 첫 화면 신뢰도 회복 |
| P1 | `중계 보기` 클릭 결과가 하이라이트 | 상태별 CTA와 상세 진입 위치 분리 | 버튼 기대와 결과 일치 |
| P1 | Widget/Live 표면 stale 불명확 | 앱 밖 표면 문구와 timestamp 강화 | 실시간 오해 감소 |
| P2 | `Live만`, `요약` 용어가 모호 | 사용자 언어로 label/copy 변경 | 학습 비용 감소 |
| P2 | 설정 제목/프리셋 affordance 혼재 | IA와 상태 표시 정리 | 설정 화면 스캔성 개선 |
| P3 | Native 앱 밖 표면 실기기 검증 부족 | iOS/Android 캡처 QA 추가 | 릴리즈 전 리스크 감소 |

## P1-1. 홈 첫 화면 CTA 잘림

### 관찰

`03-home-state.png`에서 마이팀 브리프 하단 버튼이 bottom navigation에 걸린다. 사용자는 버튼이 비활성인지, 더 내려야 하는지, 화면이 깨진 것인지 즉시 판단하기 어렵다.

관련 위치:

- `app/lib/features/home/home_screen.dart`
- `_MyTeamBriefCard`
- `app/lib/features/home/widgets/my_team_game_card.dart`
- `MainScaffold`의 bottom navigation 구조

### 원인

- 홈 화면은 카드 정보를 풍부하게 넣었지만 390x844 첫 viewport의 하단 safe area를 충분히 확보하지 못했다.
- `_MyTeamBriefCard`는 최근 3경기, 3개 metric, 2개 CTA를 모두 펼친다.
- 하단 탭은 고정인데 ListView 하단 padding과 카드 높이 설계가 이를 충분히 고려하지 않는다.

### 수정안 A: 하단 safe area 확장

ListView 또는 홈 content wrapper의 bottom padding을 bottom nav 높이 + safe area + 24px 이상으로 잡는다.

권장값:

- 기본 bottom padding: `96`
- 기기 safe area 반영: `MediaQuery.paddingOf(context).bottom + 88`
- 마지막 카드와 bottom nav 사이 최소 여백: 16px

장점:

- 구현 범위가 작다.
- 다른 홈 카드에도 일괄적으로 안전하다.

단점:

- 카드 자체가 높은 문제를 해결하지는 않는다.

### 수정안 B: 마이팀 브리프 밀도 조정

`_MyTeamBriefCard`를 첫 viewport용 compact 형태로 줄인다.

변경:

- 최근 3경기는 chip 3개를 유지하되 가로 스크롤 또는 2개 + `더보기`로 축약
- 하단 CTA 2개는 상태별 1 primary + 1 icon secondary로 조정
- metric label은 유지하되 value line-height를 줄이고 maxLines 1 적용

권장 구조:

```text
마이팀 브리프     5위 · 3.5G차
KIA 타이거즈
18:30 · 광주 · vs LG

최근 흐름     현재 순위     경기 상태
2승 1패       5위           경기종료

최근 3경기 [W LG 14:0] [W 삼성 16:7] [L 삼성 2:5]

[경기 상세] [순위]
```

장점:

- 첫 화면 정보 완성도가 올라간다.
- 디자인 시안의 dense-but-legible 원칙과 맞다.

단점:

- 시각 QA가 필요하다.

### 권장 결정

A와 B를 같이 한다. safe area만 늘리면 사용자는 여전히 너무 긴 카드를 본다. V4는 `앱을 열자마자 현재 상태 판단`이 목표라 홈 첫 화면에서 정보가 잘려 보이면 안 된다.

### DoD

- 390x844에서 마이팀 브리프 CTA가 bottom nav와 겹치지 않는다.
- 360x640에서 카드 내용이 bottom nav 아래로 가려지지 않는다.
- 390x844 첫 화면에서 홈 주요 경기 카드와 마이팀 브리프 상단이 모두 보인다.
- 카드 CTA의 터치 영역은 44px 이상이다.

## P1-2. `중계 보기`와 상세 첫 화면 불일치

### 관찰

홈의 `중계 보기`를 눌렀는데 상세 첫 화면에는 하이라이트 카드가 먼저 보인다. `tab=relay` intent가 있어도 중계 내용은 첫 viewport에 없다.

관련 위치:

- `app/lib/features/home/widgets/my_team_game_card.dart`
- `app/lib/features/home/home_screen.dart`
- `app/lib/features/game_detail/game_detail_screen.dart`
- `app/lib/features/game_detail/tabs/relay_tab.dart`

### 원인

- `MyTeamGameCard`의 `중계 보기`와 `핵심 알림`이 모두 같은 `onTap`으로 연결되어 있다.
- 경기 상태별 CTA 라벨이 분기되지 않는다.
- 상세 화면에서 하이라이트 카드가 탭보다 위에 있어, relay intent보다 하이라이트가 우선 노출된다.

### 수정안 A: 카드 콜백 분리

`MyTeamGameCard`에 callback을 분리한다.

```dart
final VoidCallback? onOpenDetail;
final VoidCallback? onOpenRelay;
final VoidCallback? onOpenAlert;
```

상태별 CTA:

| 상태 | Primary | Secondary |
| --- | --- | --- |
| 예정 | `일정 보기` | `알림 설정` |
| 라이브 | `중계 보기` | `따라가기` |
| 종료 | `경기 기록` | `하이라이트` |
| 취소/중단 | `경기 정보` | 숨김 또는 비활성 |

### 수정안 B: 상세 화면 상단 우선순위 재정렬

상세 화면의 추천 구조:

```text
Compact Score Header
Live 경기이면: 경기 따라가기 카드
Tabs: 스코어 / 중계 / 박스 / 라인업
Selected Tab Content
종료 경기이면: 하이라이트 카드
```

핵심은 `tab=relay`일 때 relay content가 첫 viewport 안에 들어오는 것이다. 하이라이트는 종료 경기에서 중요하지만, `중계 보기` intent보다 앞서면 안 된다.

### 수정안 C: 진입 intent 명시

route query를 더 명확히 한다.

- `/game/:gameId?tab=relay&entry=relay`
- `/game/:gameId?tab=score&entry=summary`
- `/game/:gameId?entry=highlight`

`entry=relay`면 상세 진입 후 하이라이트를 접거나 탭 아래로 이동한다.

### 권장 결정

A와 B를 먼저 한다. C는 추후 확장용이다. 지금 문제는 콜백과 화면 우선순위만 분리해도 해결된다.

### DoD

- live 경기에서 `중계 보기`를 누르면 relay 탭 내용이 첫 viewport에 보인다.
- 종료 경기에서 primary CTA는 `경기 기록` 또는 `경기 상세`로 표시된다.
- `핵심 알림`을 누르면 설정/권한 흐름 또는 경기 follow CTA로 이동하고, 단순 상세 이동으로 끝나지 않는다.
- 하이라이트는 종료 경기 상세에서 보이되, 사용자가 선택한 tab intent를 가리지 않는다.

## P1-3. Widget / Live 표면의 stale 가능성 불명확

### 관찰

설정의 `앱 밖 표면` 섹션은 Push, 요약, Live 표면, 위젯을 분리해 보여준다. 방향은 좋다. 하지만 위젯과 Live 표면이 실시간처럼 읽힐 수 있다.

관련 위치:

- `app/lib/features/settings/settings_screen.dart`
- `app/lib/services/widget_sync_service.dart`
- `app/lib/services/live_activity_service.dart`
- `app/ios/KboFansWidget/KboFansWidget.swift`
- `app/android/app/src/main/kotlin/com/kbofans/kbo_fans/KboFansScoreWidgetProvider.kt`
- `app/android/app/src/main/res/layout/kbo_score_widget.xml`

### 원인

- `WidgetSyncService`는 OS 정책과 background refresh 제약을 받는다.
- iOS Live Activity는 구현되어 있으나 Android는 홈 위젯만 확인되고, Android Live Update 스타일 진행형 알림은 별도 구현 확인이 안 된다.
- UI copy가 플랫폼 차이를 숨긴다.

### 수정안 A: 표면 명칭을 플랫폼/역할 기준으로 변경

현재:

- Push
- 요약
- Live 표면
- 위젯

권장:

- `바로 알림`
- `묶음 요약`
- `따라가기 화면`
- `홈 위젯`

플랫폼 보조 문구:

- iOS: `Live Activity로 잠금화면/다이내믹 아일랜드에 표시`
- Android: `홈 위젯 우선, 진행형 알림은 후속 구현`
- Widget: `OS 정책에 따라 갱신이 지연될 수 있음`

### 수정안 B: timestamp/stale copy 강화

홈 카드:

- live: `22:41 업데이트`
- final: `최종 · 22:41 업데이트`
- scheduled: `18:30 예정 · 예매 알림 가능`
- stale: `마지막 확인 22:41`

위젯:

- `업데이트 22:41` 유지
- 오래된 경우 `마지막 확인 22:41`로 문구 변경
- live 상태에서 일정 시간 이상 갱신 실패 시 `확인 필요` badge 추가

### 수정안 C: 앱 밖 표면 문서/QA 분리

네이티브 표면은 web 캡처로 충분하지 않다. 별도 QA 문서가 필요하다.

필수 캡처:

- iOS Lock Screen Live Activity
- iOS Dynamic Island compact/minimal/expanded
- iOS Widget small/medium
- Android Home Widget
- Android notification permission prompt
- Android 진행형 알림은 구현 전이면 `미구현`으로 명확히 표시

### 권장 결정

A와 B는 바로 반영한다. C는 릴리즈 전 native QA 항목으로 문서화한다.

### DoD

- 설정에서 Android 사용자가 존재하지 않는 Live 표면을 기대하지 않는다.
- 모든 앱 밖 표면에는 `업데이트 시각` 또는 stale 가능성 설명이 있다.
- live 경기 종료 시 Live Activity는 종료되고, widget은 final 상태를 표시한다.
- Android에서는 `POST_NOTIFICATIONS` 권한 요청이 사용자 액션 뒤에만 뜬다.

## P2-1. 알림 용어 정리

### 문제

`요약`, `Live만`, `Live 표면만`은 짧지만 추상적이다. 야구 앱 사용자는 기술 표면보다 "어디에 오느냐"와 "얼마나 방해하느냐"를 알고 싶다.

### 권장 용어

| 현재 | 권장 | 설명 |
| --- | --- | --- |
| 바로 | 바로 알림 | 잠금화면/푸시로 즉시 보냄 |
| 요약 | 묶음 요약 | 시작/종료/라인업처럼 묶어서 봄 |
| Live만 | 따라가기만 | 경기 따라가기 화면에만 반영 |
| Live 표면만 | 따라가기 화면만 | 푸시는 보내지 않음 |
| 끄기 | 끄기 | 유지 |

### Moment별 기본값

| Moment | 기본 전달 | 이유 |
| --- | --- | --- |
| 경기 시작 | 묶음 요약 | 사용자가 이미 알고 있을 가능성이 높음 |
| 득점 | 바로 알림 | 즉시 가치가 큼 |
| 홈런 | 바로 알림 | 야구 팬의 고가치 이벤트 |
| 역전 | 바로 알림 | 경기 맥락 변화가 큼 |
| 경기 종료 | 묶음 요약 또는 바로 알림 | 사용자 선호가 갈림 |
| 라인업 | 묶음 요약 | 즉시성보다 확인성이 큼 |
| 이닝 교대 | 따라가기만 | 너무 잦은 push 방지 |

### DoD

- 설정 row, bottom sheet, 표면 설명이 같은 용어를 쓴다.
- 사용자는 `따라가기만`을 선택하면 push가 오지 않는다는 사실을 문장으로 확인할 수 있다.
- `묶음 요약`이 실제로 어디에 도착하는지 표시한다. 아직 inbox가 없다면 `푸시 요약`인지 `앱 내 요약`인지 범위를 정한다.

## P2-2. 설정 IA와 프리셋 affordance 정리

### 문제

화면 제목과 섹션 제목이 모두 `알림 플레이북`이다. 헤더의 `내 팀 집중`은 상태인지 버튼인지 모호하다.

### 수정안

화면 구조:

```text
SETTINGS
알림
[현재 프리셋: 내 팀 집중]

마이팀
KIA 타이거즈

장면별 알림
KIA 중심 카드
Moment rows

앱 밖 표면
바로 알림 / 묶음 요약 / 따라가기 화면 / 홈 위젯

리그 전체 알림
...
```

프리셋:

- 상태만 보여줄 경우: `현재 프리셋: 내 팀 집중`
- 눌러 변경 가능할 경우: `프리셋 변경` button + bottom sheet

### DoD

- 같은 화면에서 같은 heading이 반복되지 않는다.
- button으로 보이는 요소는 실제로 눌린다.
- 상태 badge는 chevron, elevated shape, tap ripple을 쓰지 않는다.

## P2-3. 종료 경기의 CTA 언어

### 문제

종료 경기에서 `핵심 알림`은 늦다. 이미 끝난 경기에 사용자가 원하는 것은 결과, 기록, 하이라이트, 다음 경기다.

### 권장 상태별 CTA

| 상태 | Main card primary | Main card secondary | My Team Brief primary |
| --- | --- | --- | --- |
| 예정 | `경기 정보` | `예매/알림` | `일정 보기` |
| 라이브 | `중계 보기` | `따라가기` | `중계 보기` |
| 종료 | `경기 기록` | `하이라이트` | `경기 기록` |
| 취소 | `경기 정보` | 숨김 | `일정 보기` |

### DoD

- 종료 경기에서 `알림`이라는 단어가 primary CTA에 나오지 않는다.
- 라이브 경기에서 `따라가기`는 notification permission/follow 흐름으로 간다.
- 예정 경기에서 예매/알림은 ticket alert와 push permission의 차이를 명확히 구분한다.

## P3. Native 앱 밖 표면 QA 계획

### 왜 필요한가

V4의 핵심은 앱 안 화면보다 앱 밖 표면이다. Web 캡처만으로는 iOS Live Activity, Dynamic Island, Android Widget, notification permission prompt의 실제 품질을 판단할 수 없다.

### QA 매트릭스

| 플랫폼 | 표면 | 상태 | 확인할 것 |
| --- | --- | --- | --- |
| iOS | Live Activity Lock Screen | live | 점수, 이닝, 업데이트 시각, 팀 인식성 |
| iOS | Dynamic Island compact | live | 최소 정보가 과밀하지 않은지 |
| iOS | Dynamic Island expanded | live | score/inning/count hierarchy |
| iOS | Widget small | scheduled/live/final | stale 문구와 legibility |
| iOS | Widget medium | scheduled/live/final | 정보 과밀도 |
| Android | Home Widget | scheduled/live/final | 텍스트 잘림, timestamp |
| Android | Notification permission | first follow action | 권한 요청 맥락 |
| Android | 진행형 알림 | live | 구현 여부 명확화 |

### 산출물

- `artifacts/kbo-v4-native-surface-qa/ios-live-activity-lockscreen.png`
- `artifacts/kbo-v4-native-surface-qa/ios-dynamic-island-expanded.png`
- `artifacts/kbo-v4-native-surface-qa/ios-widget-small.png`
- `artifacts/kbo-v4-native-surface-qa/android-widget.png`
- `docs/UX_NATIVE_SURFACE_QA_V4_2026-05-19.md`

## 구현 순서 제안

1. Copy-only 정리: 알림 용어, 표면 설명, heading 중복 제거
2. Home CTA 상태별 라벨 분기
3. `MyTeamGameCard` callback 분리
4. Game Detail에서 `tab=relay` 진입 시 relay 우선 노출
5. Home safe area와 `_MyTeamBriefCard` compact 조정
6. Widget/Live stale timestamp copy 보강
7. Native surface QA 캡처

이 순서가 좋은 이유:

- 1~3은 리스크가 낮고 UX 혼란을 빠르게 줄인다.
- 4~5는 화면 구조 변경이라 visual regression 확인이 필요하다.
- 6~7은 native 표면 검증과 연결되어 있어 마지막에 실제 기기 기준으로 닫는 것이 맞다.

## 테스트 계획

### Web smoke

- 390x844 home
- 360x640 home
- 390x844 settings top
- 390x844 settings delivery picker
- 390x844 game detail live relay
- 390x844 game detail final score/record

### Flutter

- `cd app && fvm flutter analyze`
- `cd app && fvm flutter test test/widget_test.dart test/services/push_notification_service_test.dart`

### Interaction checks

- live: `중계 보기` -> relay content first viewport
- live: `따라가기` -> permission/follow flow
- final: `경기 기록` -> score/box/record context
- scheduled: `알림 설정` -> ticket/push distinction visible
- settings: delivery picker labels and selected state preserved after restart

## 리스크

- `요약`의 실제 제품 정의가 아직 불명확하다. push summary인지, 앱 내 notification center인지 먼저 결정해야 한다.
- Android Live Update는 OS/Material guidance상 "유한하고 사용자가 시작한 추적 경험"에 맞아야 한다. 단순 리그 경기 자동 추적은 과할 수 있다.
- 하이라이트 위치를 내리면 종료 경기 사용자는 하이라이트 발견성이 낮아질 수 있다. 종료 경기 entry에서는 하이라이트 CTA를 별도로 줘야 한다.
- Widget timestamp를 강화하면 stale 상태가 더 자주 드러난다. 하지만 숨기는 것보다 신뢰도가 높다.

## 완료 기준

- P1 3개 항목이 실제 390x844 캡처에서 해소된다.
- 사용자가 `따라가기`, `바로 알림`, `묶음 요약`, `홈 위젯`의 차이를 설정 화면 안에서 이해할 수 있다.
- 종료 경기에서 알림 중심 CTA가 사라진다.
- Native 앱 밖 표면의 구현/미구현 상태가 문서와 화면 copy에서 일치한다.
- UX 점수 재평가 기준 90/100 이상을 목표로 한다.

자가점검: 96/100  
감점 사유: 실제 native 캡처 보강은 구현 이후 QA 단계로 남는다.
