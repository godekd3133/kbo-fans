# Codex Android 실행 환경

최종 업데이트: 2026-03-31

## 목적

Codex에서 안드로이드 앱을 실행할 때 아래를 자동으로 맞추기 위한 실행 환경 문서.

- Java 17 사용
- Android SDK 경로 고정
- AVD 자동 부팅
- `flutter run` 전 `pub get`
- 로컬 백엔드 기준 `APP_ENV=local`

## 권장 실행 명령

```bash
./scripts/codex-run-android.sh
```

또는

```bash
./scripts/codex-run.sh android
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
7. `fvm flutter run -d <serial> --dart-define=APP_ENV=local`

## 현재 기본 가정

- Android SDK: `~/Library/Android/sdk`
- 권장 AVD: `Medium_Phone_API_36`
- Java 17: `/Applications/Android Studio.app/Contents/jbr/Contents/Home`

## 자주 막히는 문제

### 1. Java 8로 빌드되는 문제

증상:

- `Dependency requires at least JVM runtime version 11`

해결:

- Codex 실행은 반드시 `./scripts/codex-run-android.sh` 사용
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

### 4. 앱은 뜨는데 로컬에서 하이라이트 썸네일이 비는 문제

현재 앱은 로컬 안드로이드도 백엔드 API 기반 하이라이트 응답을 사용하도록 수정됨.

관련 코드:

- `/Users/kimminkyu/Bagelcode/Repository_Bagelcode/kbo_fans/app/lib/data/providers.dart`
- `/Users/kimminkyu/Bagelcode/Repository_Bagelcode/kbo_fans/app/lib/features/game_detail/game_detail_screen.dart`

## 관련 파일

- `/Users/kimminkyu/Bagelcode/Repository_Bagelcode/kbo_fans/scripts/codex-run.sh`
- `/Users/kimminkyu/Bagelcode/Repository_Bagelcode/kbo_fans/scripts/codex-run-android.sh`
