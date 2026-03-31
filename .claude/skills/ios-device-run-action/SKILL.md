---
name: ios-device-run-action
description: Use when the iOS run action should target a connected physical device first, or when Flutter sees the device but Xcode cannot build for it because destination or Components state is out of sync.
---

# iOS Device Run Action

## Use this when
- `scripts/codex-run.sh ios` 가 연결된 실제 iPhone/iPad를 우선 대상으로 잡아야 한다.
- `flutter devices` 에서는 기기가 보이는데 `xcodebuild` destination 에러가 난다.
- Xcode Components 에 설치된 것으로 보이는데도 `iOS xx.x is not installed` 가 뜬다.

## Primary files
- `scripts/codex-run.sh`
- `scripts/codex-run-ios.sh`
- `app/ios/Runner.xcworkspace`

## Workflow
1. `flutter devices --machine` 로 iOS physical device를 우선 찾는다.
2. physical device가 있으면 UDID로 `flutter run -d <device-id>` 한다.
3. physical device가 없으면 시뮬레이터로 fallback 한다.
4. 실행 전에 `xcodebuild -showdestinations` 로 destination eligibility를 확인한다.
5. `flutter devices` 와 `xcodebuild` 결과가 어긋나면:
   - `xcode-select -p`
   - `xcodebuild -version`
   - `xcodebuild -showdestinations`
   를 같이 확인한다.
6. 필요하면 다음 액션을 안내한다.
   - `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`
   - `sudo xcodebuild -runFirstLaunch`
   - Xcode 종료/재실행
   - `Xcode > Settings > Components` 재설치 확인

## Repository-specific insights
- 이 저장소는 Codex 실행 액션을 `scripts/` 아래 래퍼로 유지한다.
- 실사용성 기준 iOS 액션은 `연결 기기 우선, 시뮬레이터 fallback` 이 맞다.
- `~/Library/Developer/Xcode/iOS DeviceSupport/...` 캐시가 있어도, `xcodebuild` destination 에서는 platform 미설치로 판정할 수 있다.
