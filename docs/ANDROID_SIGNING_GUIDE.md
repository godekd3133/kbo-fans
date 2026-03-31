# Android 서명 / Keystore 가이드

## 목적

이 문서는 KBO Fans Android 앱을 Google Play 내부 테스트 또는 비공개 테스트로 배포하기 위해 필요한 release signing 설정을 정리한다.

## 현재 상태

현재 Android release 빌드는 임시로 debug signing 을 사용하고 있다.

확인 파일:

- `app/android/app/build.gradle.kts`

현재 상태 요약:

- `release` 빌드가 `signingConfigs.getByName("debug")` 를 사용 중
- 이 상태로는 Google Play 배포용 release signing 설정이 완성되지 않음

즉, 친구에게 Android 설치 링크를 주려면 먼저 release keystore 설정을 분리해야 한다.

## 목표 상태

목표는 아래 3가지를 갖추는 것이다.

1. 업로드용 keystore 생성
2. 로컬 비밀값 파일 분리
3. `build.gradle.kts` 에서 release signingConfig 연결

## 1. Keystore 생성

예시 명령:

```bash
keytool -genkeypair \
  -v \
  -keystore ~/keystores/kbo-fans-upload.jks \
  -keyalg RSA \
  -keysize 2048 \
  -validity 10000 \
  -alias kbo-fans-upload
```

생성 후 반드시 별도 보관:

- keystore 파일 경로
- store password
- key alias
- key password

## 2. `key.properties` 파일 생성

권장 위치:

- `app/android/key.properties`

예시 파일:

- `app/android/key.properties.example`

예시 내용:

```properties
storePassword=YOUR_STORE_PASSWORD
keyPassword=YOUR_KEY_PASSWORD
keyAlias=kbo-fans-upload
storeFile=/Users/kimminkyu/keystores/kbo-fans-upload.jks
```

주의:

- 실제 비밀번호는 Git에 올리면 안 됨
- `storeFile` 은 절대 경로가 가장 안전함

## 3. `.gitignore` 확인

아래 파일은 Git에 올라가면 안 된다.

- `app/android/key.properties`
- `.jks`
- `.keystore`

권장 추가 항목:

```gitignore
app/android/key.properties
*.jks
*.keystore
```

## 4. `build.gradle.kts` 수정 방향

현재 저장소는 `key.properties` 가 있으면 release signing 을 사용하고, 없으면 개발 편의를 위해 debug signing 으로 fallback 되도록 정리되어 있다.

목표 형태:

```kotlin
import java.util.Properties

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(keystorePropertiesFile.inputStream())
}

android {
    signingConfigs {
        create("release") {
            storeFile = file(keystoreProperties["storeFile"] as String)
            storePassword = keystoreProperties["storePassword"] as String
            keyAlias = keystoreProperties["keyAlias"] as String
            keyPassword = keystoreProperties["keyPassword"] as String
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}
```

## 5. Release 빌드 생성

명령:

```bash
cd app
fvm flutter clean
fvm flutter pub get
fvm flutter build appbundle --release
```

출력물:

- `app/build/app/outputs/bundle/release/app-release.aab`

## 6. Play Console 업로드

추천 순서:

1. Play Console 앱 생성
2. Internal testing 선택
3. `app-release.aab` 업로드
4. 테스터 이메일 또는 링크 설정
5. 친구에게 링크 전달

## 체크리스트

- [ ] upload keystore 생성
- [ ] keystore 비밀번호 별도 보관
- [ ] `app/android/key.properties` 생성
- [ ] `.gitignore` 에 keystore / key.properties 반영
- [ ] `build.gradle.kts` 에 release signingConfig 연결
- [ ] `flutter build appbundle --release` 성공
- [ ] Play Console Internal testing 업로드 성공

## 현재 저장소에서 먼저 고쳐야 할 점

- `app/android/app/build.gradle.kts` 는 이제 `key.properties` 기반 release signing 구조를 사용함
- Play 배포 전에는 반드시 `app/android/key.properties` 와 upload keystore 를 준비해야 함
