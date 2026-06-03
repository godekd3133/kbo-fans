# iOS TestFlight 체크리스트

## 목적

이 문서는 KBO Fans 앱을 iPhone 친구에게 TestFlight로 배포하기 전 필요한 준비 항목을 짧고 실행 가능하게 정리한다.

## 현재 상태

현재 저장소는 Flutter iOS 프로젝트를 포함하고 있고, Firebase plugin 요구사항에 맞춰 iOS deployment target 을 `15.0` 으로 올려 둔 상태다.

하지만 실제 TestFlight 업로드 전에는 아래 항목을 하나씩 확인해야 한다.

## 1. Apple 계정 / App Store Connect

- [ ] Apple Developer Program 가입 완료
- [ ] App Store Connect 접근 가능
- [ ] 새 앱 생성 완료
- [ ] Bundle ID 일치

현재 Bundle ID:

- `com.kbofans.kboFans`

## 2. Xcode / Signing

- [ ] Xcode에서 `Runner.xcworkspace` 열림
- [ ] `Signing & Capabilities` 에 올바른 Team 설정
- [ ] 자동 서명 또는 배포용 프로비저닝 정상
- [ ] `Product > Destination` 에 유효한 iOS 대상 표시
- [ ] `Product > Archive` 실패 없이 진행 가능

## 3. Firebase / 런타임 설정

Firebase를 실제로 사용할 계획이면:

- [ ] `GoogleService-Info.plist` 포함
- [ ] Firebase 프로젝트와 Bundle ID 일치
- [ ] 푸시를 쓸 경우 APNs / FCM 설정 점검
- [ ] 앱 종료 후 Dynamic Island 갱신을 시연할 경우 운영 backend / APNs ActivityKit 설정 점검
  - 세부 항목: `docs/PUSH_LIVE_ACTIVITY_BACKEND_SETUP.md`
- [ ] 운영 backend `GET /api/push/config-status`의 `readyForIphoneOnlyDemo=true` 확인
- [ ] AWS sync worker 또는 scheduler가 30~60초 간격으로 scoreboard sync를 실행 중인지 확인
- [ ] TestFlight release build에 운영 `API_BASE_URL`이 주입됐는지 확인
  - CI: `release_api_base_url` input 또는 `RELEASE_API_BASE_URL` variable/secret
  - 로컬: `RELEASE_API_BASE_URL=https://... ./scripts/codex-run-ios-release.sh`

주의:

- plist 가 없으면 Firebase 기반 기능이 비정상 동작할 수 있음

## 4. 앱 메타데이터

- [ ] 앱 이름 확인
- [ ] 앱 아이콘 확인
- [ ] 버전(`versionName`) / 빌드번호 증가 정책 정리
- [ ] 개인정보 처리 / 테스트 설명 필요 시 준비

## 5. Flutter / Pod 정리

권장 명령:

```bash
cd app
fvm flutter clean
fvm flutter pub get
cd ios
pod install
```

## 6. Archive

Xcode에서:

1. `Runner.xcworkspace` 열기
2. 상단 Scheme `Runner` 선택
3. Destination 을 `Any iOS Device` 또는 유효한 iOS destination 으로 설정
4. `Product > Archive`

성공 기준:

- Organizer 에 새 Archive 가 생성됨

## 7. TestFlight 업로드

Organizer 에서:

1. Archive 선택
2. `Distribute App`
3. `App Store Connect`
4. `Upload`

업로드 후:

- [ ] App Store Connect > TestFlight 에 빌드 표시
- [ ] processing 완료

## GitHub Actions 서명 빌드 시크릿

GitHub Actions 에서 signed IPA 까지 생성하려면 아래 시크릿이 필요하다.

- `IOS_CERTIFICATE_P12_BASE64`
- `IOS_CERTIFICATE_PASSWORD`
- `IOS_RUNNER_PROFILE_BASE64`
- `IOS_WIDGET_PROFILE_BASE64`
- `IOS_RUNNER_PROFILE_SPECIFIER`
- `IOS_WIDGET_PROFILE_SPECIFIER`
- `IOS_TEAM_ID`
- 선택: `IOS_EXPORT_METHOD`
  - 기본값은 `app-store`

이 시크릿이 준비되면 `Actions > App Build Artifacts` 에서 `platform=ios`, `build_signed_ios_ipa=true` 로 실행해 `.ipa` 를 아티팩트로 받을 수 있다.

주의:

- 위젯 extension 이 있으므로 Runner 와 Widget 두 provisioning profile 을 모두 준비해야 한다.
- 시크릿이 없으면 기본 워크플로우는 simulator 용 unsigned 앱만 생성한다.

## 8. 내부 테스트

- [ ] 내부 테스터 그룹 생성
- [ ] 빌드 연결
- [ ] 친구 Apple ID 또는 팀원 계정 추가

## 9. 외부 테스트

- [ ] 외부 테스터 그룹 생성
- [ ] Beta App Review 제출
- [ ] 승인 후 공개 링크 또는 이메일 공유

## 최종 체크리스트

- [ ] Apple Developer Program 준비
- [ ] App Store Connect 앱 생성
- [ ] Bundle ID 일치
- [ ] Signing Team 설정 완료
- [ ] Firebase plist 점검
- [ ] Pod install 성공
- [ ] Archive 성공
- [ ] TestFlight 업로드 성공
- [ ] 내부 테스터 배포 성공
- [ ] 외부 테스트 필요 시 Beta App Review 제출

## 메모

- iOS는 친구에게 설치시키는 경로로 `TestFlight` 가 가장 현실적이다
- 로컬 실행이 불안정하면 TestFlight 준비 전 `Archive` 가능 상태부터 먼저 확보해야 한다
