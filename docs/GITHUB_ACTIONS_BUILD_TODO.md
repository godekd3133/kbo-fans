# GitHub Actions 빌드 설정 TODO

## 목적

이 문서는 `.github/workflows/app-build-artifacts.yml` 를 실제로 usable 상태로 만들기 위해 남아 있는 수작업 항목을 정리한다.

대상:

- Android release `apk` / `aab`
- iOS simulator app zip
- iOS signed `ipa`
- Web static zip

## 현재 상태

- GitHub Actions 수동 워크플로우는 이미 저장소에 추가됨
- 플랫폼/환경별 아티팩트 업로드 경로도 정의됨
- workflow 내부 signing/config/metadata 파일 생성은 heredoc 없이 동작하도록 정리해 runner 들여쓰기 영향을 받지 않음
- `actions/checkout` / `actions/setup-python`은 Node.js 24 대응 major인 `@v6` 사용
- `web/release` 원격 run `26931917852`는 backend tests, web release build, metadata, artifact upload까지 통과함
- Android/iOS GitHub Secrets 등록과 실제 원격 실행 검증은 아직 안 끝남
- release API backend는 아직 없다. 운영 API 준비 항목은 `docs/RELEASE_API_BACKEND_TODO.md` 를 기준으로 추적한다.

## 우선순위

1. Android signing secrets 등록
2. iOS signing secrets 등록
3. Web / Android / iOS workflow 수동 실행
4. 각 아티팩트 다운로드 및 설치/업로드 검증
5. 실패 로그 기준 보완

## GitHub 저장소 설정

위치:

- GitHub Repository > `Settings > Secrets and variables > Actions`

필수 확인:

- Actions 사용 가능 상태인지 확인
- 기본 브랜치에서 workflow 실행 권한이 막혀 있지 않은지 확인
- private repository 에서 artifact retention 정책이 조직 정책과 충돌하지 않는지 확인

## Android TODO

### Secrets 등록

- [ ] `ANDROID_KEYSTORE_BASE64`
- [ ] `ANDROID_KEYSTORE_PASSWORD`
- [ ] `ANDROID_KEY_ALIAS`
- [ ] `ANDROID_KEY_PASSWORD`

준비 방법:

```bash
base64 -i ~/keystores/kbo-fans-upload.jks | pbcopy
```

확인 포인트:

- `ANDROID_KEYSTORE_BASE64` 는 줄바꿈/공백 없이 붙여넣는 편이 안전함
- alias / password 값이 실제 keystore 와 일치해야 함
- keystore 가 Play Console 업로드 키인지 확인

### 실행

- [ ] `Actions > App Build Artifacts`
- [ ] `platform=android`
- [ ] `app_environment=release`
- [ ] workflow 실행

### 검증

- [ ] `android-release-apk` artifact 다운로드
- [ ] `android-release-aab` artifact 다운로드
- [ ] metadata 파일에서 `signing=release-keystore` 확인
- [ ] `aab` 를 Play Console internal testing 에 업로드 가능한지 확인

### 실패 시 확인

- `Keystore was tampered with, or password was incorrect`
  - store password 재확인
- `No key with alias`
  - `ANDROID_KEY_ALIAS` 재확인
- debug signing 으로 나온 경우
  - secrets 네 개가 모두 등록됐는지 확인

## iOS TODO

### Secrets 등록

- [ ] `IOS_CERTIFICATE_P12_BASE64`
- [ ] `IOS_CERTIFICATE_PASSWORD`
- [ ] `IOS_RUNNER_PROFILE_BASE64`
- [ ] `IOS_WIDGET_PROFILE_BASE64`
- [ ] `IOS_RUNNER_PROFILE_SPECIFIER`
- [ ] `IOS_WIDGET_PROFILE_SPECIFIER`
- [ ] `IOS_TEAM_ID`
- [ ] 필요 시 `IOS_EXPORT_METHOD`

필수 전제:

- Runner bundle id: `com.kbofans.kboFans`
- Widget bundle id: `com.kbofans.kboFans.KboFansWidget`
- widget extension 용 provisioning profile 이 별도로 필요함

준비 방법 예시:

```bash
base64 -i Certificates.p12 | pbcopy
base64 -i Runner.mobileprovision | pbcopy
base64 -i KboFansWidget.mobileprovision | pbcopy
```

### 1차 실행: simulator 빌드

- [ ] `platform=ios`
- [ ] `app_environment=release`
- [ ] `build_signed_ios_ipa=false`
- [ ] workflow 실행

검증:

- [ ] `ios-release-simulator-app` artifact 다운로드
- [ ] zip 내부 `Runner.app` 존재 확인

### 2차 실행: signed ipa 빌드

- [ ] `platform=ios`
- [ ] `app_environment=release`
- [ ] `build_signed_ios_ipa=true`
- [ ] workflow 실행

검증:

- [ ] `ios-release-ipa` artifact 다운로드
- [ ] `.ipa` 생성 여부 확인
- [ ] metadata 파일의 `team_id` 값 확인
- [ ] TestFlight 업로드 가능 여부 확인

### 실패 시 확인

- `Missing required secret`
  - secret 누락
- `No profiles for ... were found`
  - profile specifier 또는 bundle id 불일치
- `requires a provisioning profile`
  - Runner / Widget 둘 중 하나 누락
- `No signing certificate`
  - p12 또는 password 불일치

## Web TODO

### 실행

- [ ] `platform=web`
- [ ] `app_environment=dev`
- [ ] workflow 실행
- [x] `platform=web` (`release`)
- [x] `app_environment=release`
- [x] workflow 실행 (`26931917852`)

### 검증

- [ ] `web-dev` artifact 다운로드
- [x] `web-release` artifact 다운로드
- [ ] zip 압축 해제 후 정적 서버에서 열리는지 확인
- [ ] `release` 빌드가 운영 API 기준으로 뜨는지 확인

## 권장 검증 순서

1. Web `release`
2. Android `release`
3. iOS simulator `release`
4. iOS signed `ipa`

이 순서가 좋은 이유:

- Web 이 가장 빠르게 workflow 자체 이상 여부를 볼 수 있음
- Android 는 signing 검증이 비교적 단순함
- iOS signed `ipa` 가 가장 민감하고 준비물이 많음

## 완료 기준

아래가 모두 충족되면 이 문서의 목적은 완료다.

- [ ] Android release `apk`, `aab` 가 GitHub Actions 에서 정상 생성됨
- [ ] iOS simulator app zip 이 정상 생성됨
- [ ] iOS signed `ipa` 가 정상 생성됨
- [ ] Web static zip 이 정상 생성됨
- [ ] Play Console internal testing 업로드 가능 확인
- [ ] TestFlight 업로드 가능 확인

## 관련 문서

- `README.md`
- `docs/DISTRIBUTION_GUIDE.md`
- `docs/ANDROID_SIGNING_GUIDE.md`
- `docs/IOS_TESTFLIGHT_CHECKLIST.md`
- `.github/workflows/app-build-artifacts.yml`
