# Codex Android 실행 환경

최종 업데이트: 2026-06-04

## 목적

Codex에서 안드로이드 앱을 실행할 때 아래를 자동으로 맞추기 위한 실행 환경 문서.

- Java 17 사용
- Android SDK 경로 고정
- AVD 자동 부팅
- `flutter run` 전 `pub get`
- no-backend direct data 기준 `APP_ENV=local`
- release 검증도 backend API 없이 `APP_ENV=release`

## 권장 실행 명령

```bash
./scripts/codex-run-android.sh
```

또는

```bash
./scripts/codex-run.sh android
```

no-backend release 경로로 검증할 때:

```bash
./scripts/codex-run-android-release.sh
```

또는

```bash
./scripts/codex-run.sh android-release
```

## 스크립트가 자동으로 하는 일

1. `JAVA_HOME` 확인
2. Android Studio JBR(Java 17) 자동 선택
3. Android SDK 경로 탐색
   - `ANDROID_SDK_ROOT`
   - `ANDROID_HOME`
   - 기본값 `~/Library/Android/sdk`
4. 실행 중인 에뮬레이터 탐색
5. 없으면 AVD 자동 부팅
   - 우선값: `Medium_Phone_API_36`
6. `sys.boot_completed=1` 대기
7. macOS에서 Gradle/JDK spawn helper 문제가 재발하지 않도록 `GRADLE_OPTS=-Djdk.lang.Process.launchMechanism=FORK` 주입
8. `fvm flutter run -d <serial> --dart-define=APP_ENV=local --dart-define=PREFER_DIRECT_SCRAPE=true`

release 경로도 backend API health gate 없이 `APP_ENV=release --dart-define=PREFER_DIRECT_SCRAPE=true` 로 실행한다. 단, push 등록을 위해 운영 `API_BASE_URL`은 함께 주입한다.

## 현재 기본 가정

- Android SDK: `~/Library/Android/sdk`
- 권장 AVD: `Medium_Phone_API_36`
- Java 17: `/Applications/Android Studio.app/Contents/jbr/Contents/Home`

## 자주 막히는 문제

### 1. Java 8로 빌드되는 문제

증상:

- `Dependency requires at least JVM runtime version 11`

해결:

- Codex local 실행은 반드시 `./scripts/codex-run-android.sh` 사용
- 스크립트가 Android Studio JBR(Java 17)을 자동 선택함

### 2. Android SDK Platform 36 손상

증상:

- `Archive is not a ZIP archive`
- `platforms;android-36` 설치 실패

확인 파일:

```bash
ls ~/Library/Android/sdk/platforms/android-36/android.jar
```

없으면 SDK가 불완전한 상태.

### 3. 에뮬레이터는 뜨는데 adb에 안 잡힘

확인:

```bash
~/Library/Android/sdk/platform-tools/adb devices -l
```

### 4. Glance alpha가 compileSdk / AGP를 끌어올리는 문제

증상:

- `Dependency 'androidx.glance:glance-appwidget:1.3.0-alpha01' requires ... compile against version 37`
- `requires Android Gradle plugin 9.1.0 or higher`

원인:

- `home_widget 0.9.0` Android plugin이 `androidx.glance:glance-appwidget:1.+` 동적 버전을 선언한다.
- 최신 alpha가 잡히면 현재 `compileSdk 36` / Android Gradle Plugin `8.11.1` 조합과 충돌한다.

해결:

- repo Gradle에서 `androidx.glance` 그룹을 `1.0.0`으로 고정한다.
- 확인 명령:

```bash
cd app/android
./gradlew :app:dependencies --configuration debugRuntimeClasspath | rg -n "androidx.glance:glance-appwidget|remote-creation" -C 2
```

기대값:

- `androidx.glance:glance-appwidget:1.+ -> 1.0.0`
- `androidx.compose.remote:remote-creation-*` alpha가 dependency tree에서 사라짐

### 5. macOS JDK spawn helper 실패

증상:

- `Failed to exec spawn helper`
- `A problem occurred starting process 'Gradle build daemon'`

원인:

- macOS JDK process launcher가 Gradle daemon spawn 단계에서 실패할 수 있다.

해결:

- Codex Android 실행 스크립트는 macOS에서 `GRADLE_OPTS=-Djdk.lang.Process.launchMechanism=FORK`를 자동 주입한다.
- 수동 Gradle 검증 시에도 같은 옵션을 붙인다.

```bash
cd app/android
GRADLE_OPTS="-Djdk.lang.Process.launchMechanism=FORK" ./gradlew :app:assembleDebug --no-daemon
```

### 4. 앱은 뜨는데 로컬에서 하이라이트 썸네일이 비는 문제

현재 앱은 로컬 안드로이드도 백엔드 API 기반 하이라이트 응답을 사용하도록 수정됨.

관련 코드:

- `/Users/kimminkyu/Bagelcode/Repository_Bagelcode/kbo_fans/app/lib/data/providers.dart`
- `/Users/kimminkyu/Bagelcode/Repository_Bagelcode/kbo_fans/app/lib/features/game_detail/game_detail_screen.dart`

## 관련 파일

- `/Users/kimminkyu/Bagelcode/Repository_Bagelcode/kbo_fans/scripts/codex-run.sh`
- `/Users/kimminkyu/Bagelcode/Repository_Bagelcode/kbo_fans/scripts/codex-run-android.sh`
- `/Users/kimminkyu/Bagelcode/Repository_Bagelcode/kbo_fans/scripts/codex-run-android-release.sh`
