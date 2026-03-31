# iOS Live Activity / Widget Skill

## When To Use

- iOS WidgetKit, Live Activity, Dynamic Island 를 수정할 때
- 홈 위젯과 Live Activity 간 선택 우선순위를 맞출 때
- App Group, widget sync, resumed 재동기화 흐름을 점검할 때

## Files To Check First

- `app/lib/services/widget_sync_service.dart`
- `app/lib/services/live_activity_service.dart`
- `app/lib/main.dart`
- `app/ios/Runner/AppDelegate.swift`
- `app/ios/Runner/BackgroundIntent.swift`
- `app/ios/KboFansWidget/KboFansWidget.swift`
- `app/ios/Runner.xcodeproj/project.pbxproj`

## Working Rules

- Live Activity 선택 규칙은 문서와 코드에서 같이 유지한다.
  1. 진행중인 마이팀 경기
  2. 진행중인 다른 경기
  3. 오늘 마이팀 예정 경기
  4. 오늘 다른 예정 경기
- 홈 위젯과 Live Activity 동기화는 가능한 한 같은 scoreboard payload 를 사용한다.
- duplicate update 는 signature 비교로 막는다.
- 앱 resumed 시 scoreboard invalidate 를 통해 재동기화한다.
- Dynamic Island 는 UI만 구현해도 끝난 게 아니다.
  - Widget extension target membership
  - App Group entitlements
  - real device verification
  를 체크한다.

## Done Criteria

- Flutter -> native channel -> ActivityKit 경로가 끊기지 않는다
- 홈 화면 밖에서도 동기화가 유지된다
- 실기기 확인 필요 여부를 문서/답변에 명시한다

