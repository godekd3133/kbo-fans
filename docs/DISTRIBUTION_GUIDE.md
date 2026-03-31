# 배포 가이드

## 목적

이 문서는 KBO Fans 앱을 친구나 외부 테스터에게 설치하게 하는 현실적인 배포 경로를 정리한다.

현재 저장소 기준으로는 아래 3개 경로를 우선 고려한다.

- iOS: TestFlight
- Android: Google Play 내부 테스트 / 비공개 테스트
- 빠른 UI 공유: Web

## 현재 프로젝트 상태 요약

- 앱: Flutter + Dart
- 백엔드: FastAPI
- 웹 실행: 가능 (`./scripts/codex-run-web.sh`)
- iOS 실행: Xcode / iOS platform support 상태에 영향 받음
- Android 실행: 에뮬레이터 또는 실제 기기 준비 필요

즉, 친구에게 "설치"를 시키려면 웹 링크 공유만으로는 부족하고, 플랫폼별 배포 절차가 필요하다.

## iOS 배포

### 가장 현실적인 방법: TestFlight

친구가 iPhone에서 설치하게 하려면 가장 깔끔한 방법은 TestFlight다.

특징:

- Apple 공식 베타 배포 경로
- 이메일 또는 공개 링크로 테스터 초대 가능
- 외부 테스터 배포는 첫 빌드 기준 TestFlight App Review 필요
- 최대 10,000명 외부 테스터 초대 가능

공식 문서:

- Apple TestFlight 개요: https://developer.apple.com/testflight/
- 외부 테스터 초대: https://developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers

### iOS 배포 전 체크리스트

1. Apple Developer Program 계정 준비
2. App Store Connect 앱 등록
3. iOS 빌드/서명 정상화
4. Firebase 설정 파일 필요 시 `GoogleService-Info.plist` 포함
5. Xcode Archive 생성
6. TestFlight 업로드
7. 내부/외부 테스터 초대

### iOS TestFlight 실제 순서

#### 1. App Store Connect 준비

해야 할 일:

- App Store Connect에서 새 앱 생성
- Bundle ID를 현재 앱과 일치시킴
- 앱 이름, 기본 언어, SKU 입력

현재 확인된 iOS Bundle ID:

- `com.kbofans.kboFans`

확인 파일:

- `app/ios/Runner.xcodeproj/project.pbxproj`

#### 2. iOS 로컬 설정 점검

필수 확인:

- Xcode Signing Team 설정
- 실제 Archive 가능한 Xcode / platform support 상태
- Firebase를 쓸 경우 `GoogleService-Info.plist` 포함 여부
- 배포 버전에 맞는 앱 아이콘 / 런치 설정 점검

권장 점검:

- `Product > Destination` 에서 유효한 iOS 대상 확인
- `Product > Archive` 가 실패하지 않는지 확인

#### 3. Flutter iOS 빌드 점검

권장 명령:

```bash
cd app
fvm flutter clean
fvm flutter pub get
cd ios
pod install
```

그 다음 Xcode에서:

- `Runner.xcworkspace` 열기
- `Any iOS Device` 또는 유효한 iOS destination 선택
- `Product > Archive`

#### 4. Archive 업로드

Archive 완료 후:

- Xcode Organizer 열기
- 생성된 Archive 선택
- `Distribute App`
- `App Store Connect`
- `Upload`

#### 5. TestFlight 내부 테스트

업로드 후:

- App Store Connect > TestFlight
- 처리 완료까지 대기
- 내부 테스터 그룹 추가
- Apple 계정이 있는 팀원/친구 초대

장점:

- 가장 빠르게 iPhone 친구가 설치 가능
- 외부 심사 없이 내부 테스터부터 확인 가능

#### 6. TestFlight 외부 테스트

더 넓게 배포하려면:

- 외부 테스터 그룹 생성
- 빌드 선택
- Beta App Review 제출
- 승인 후 공개 링크 또는 이메일 초대

### iOS 체크리스트 요약

- [ ] Apple Developer Program 계정 있음
- [ ] App Store Connect 앱 생성 완료
- [ ] Bundle ID 일치
- [ ] Signing Team 설정 완료
- [ ] Firebase plist 포함 여부 확인
- [ ] Xcode Archive 성공
- [ ] TestFlight 빌드 업로드 성공
- [ ] 내부 테스터 추가
- [ ] 외부 배포 시 Beta App Review 제출

### 현재 저장소 기준 iOS 주의점

- 현재 로컬 환경에서 iOS 실기기/시뮬레이터 실행은 Xcode 버전과 platform support 상태의 영향을 받는다.
- TestFlight 배포를 하려면 로컬에서 최소 한 번은 Archive 가능한 상태로 정리해야 한다.
- Firebase Core / Messaging 사용 중이므로 iOS 설정 파일 누락 시 런타임에서 기능 일부가 비정상 동작할 수 있다.

## Android 배포

### 가장 현실적인 방법: Google Play 테스트 트랙

Android는 iOS보다 배포 진입장벽이 낮다.

추천 경로:

- Internal testing
- Closed testing
- 필요 시 Open testing

공식 문서:

- Android App Bundle 테스트 배포 가이드: https://developer.android.com/guide/app-bundle/test

### Android 배포 전 체크리스트

1. Google Play Console 앱 생성
2. Android 서명 키 준비
3. Release 빌드 생성
4. `aab` 업로드
5. Internal/Closed testing 트랙 배포
6. 친구를 테스터로 초대

### Android 내부 테스트 실제 순서

#### 1. Play Console 앱 생성

해야 할 일:

- Google Play Console에서 새 앱 생성
- 앱 이름, 기본 언어, 앱/게임 여부 설정
- 테스트 앱 기준 기본 정보 입력

#### 2. Android 서명 준비

필수 확인:

- 업로드 키 / keystore 준비
- `key.properties` 또는 CI 비밀값 정리
- release signing 설정 점검

현재 저장소에서는 서명 설정이 별도로 정리돼 있어야 하므로, 실제 배포 전 keystore 경로와 비밀번호 관리 방식을 확정해야 한다.

#### 3. Android App Bundle 생성

권장 명령:

```bash
cd app
fvm flutter clean
fvm flutter pub get
fvm flutter build appbundle --release
```

출력물:

- `app/build/app/outputs/bundle/release/app-release.aab`

#### 4. Internal testing 업로드

Play Console에서:

- Testing > Internal testing
- 새 릴리즈 생성
- `app-release.aab` 업로드
- 릴리즈 노트 입력
- 저장 후 배포

#### 5. 테스터 추가

방법:

- 이메일 리스트로 추가
- Google Group 기반 추가
- 생성된 테스트 링크 공유

친구가 할 일:

- 테스트 링크 열기
- 테스터 등록
- Play Store에서 앱 설치

#### 6. Closed testing 확장

친구 몇 명보다 더 넓게 보려면:

- Closed testing 트랙 생성
- 별도 테스터 그룹 운영
- 안정화 후 Open testing 또는 Production 전환

### Android 체크리스트 요약

- [ ] Play Console 앱 생성 완료
- [ ] 업로드 키 / keystore 준비
- [ ] release signing 설정 완료
- [ ] `flutter build appbundle --release` 성공
- [ ] Internal testing 릴리즈 업로드
- [ ] 테스터 링크 생성
- [ ] 친구 초대 완료

### Android 빠른 공유

정식 테스트 트랙이 가장 안정적이지만, 상황에 따라 quick sharing 같은 빠른 테스트 공유도 가능하다.

다만 수업/실서비스 기준으로는 Play Console 테스트 트랙을 우선 추천한다.

## Web 공유

설치가 아니라 빠른 확인이 목적이면 웹이 가장 쉽다.

실행:

```bash
./scripts/codex-run-web.sh
```

장점:

- 친구가 브라우저로 바로 확인 가능
- iOS / Android 서명 이슈 없이 UI와 흐름 검증 가능

한계:

- 네이티브 푸시
- 위젯
- 일부 모바일 플랫폼 연동 기능

이런 기능은 웹에서 동일하게 검증할 수 없다.

## 추천 전략

현재 프로젝트 상태에서는 아래 순서를 추천한다.

1. Web으로 빠르게 공유
2. Android 내부 테스트 트랙 준비
3. iOS TestFlight 준비

이 순서가 가장 빠르고, 플랫폼별 막힘도 적다.

## 바로 실행할 다음 액션

### 가장 빠른 공유

- 친구에게 오늘 바로 보여주고 싶다:
  - Web 실행 후 링크/화면 공유

### 설치까지 시키고 싶다

- Android 친구가 더 많다:
  - Android Internal testing 먼저
- iPhone 친구에게 먼저 설치시키고 싶다:
  - TestFlight 준비

## 현재 프로젝트 기준 우선 정리 항목

- iOS Archive 가능한 Xcode 환경 확정
- Android release signing 설정 정리
- Firebase 설정 파일 존재 여부 정리
- 앱 아이콘 / 앱 이름 / 버전 정책 정리

## Codex 실행 액션

Codex 앱에서 플랫폼별 실행 경로는 아래 스크립트로 분리되어 있다.

- iOS: `./scripts/codex-run-ios.sh`
- Android: `./scripts/codex-run-android.sh`
- Web: `./scripts/codex-run-web.sh`

## 메모

- iOS는 단순히 `ipa`를 보내는 방식보다 TestFlight가 현실적이다.
- Android는 테스트 트랙 진입이 빠르므로 친구 배포 첫 단계로 적합하다.
- "친구가 바로 설치"가 목적이면 현재 단계에서는 Web 또는 Android internal testing 이 가장 빠르다.

## 관련 문서

- Android 서명 세부 가이드: `docs/ANDROID_SIGNING_GUIDE.md`
- iOS TestFlight 체크리스트: `docs/IOS_TESTFLIGHT_CHECKLIST.md`
