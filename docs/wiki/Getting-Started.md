# 시작하기

## 준비

Git, Flutter SDK, Dart, Python 3.9 이상이 필요합니다. Dart 제약은 `app/pubspec.yaml`의 `^3.11.4`를 확인합니다. iOS 개발은 Xcode와 대상 iOS 플랫폼 지원, Android 개발은 Android SDK와 기기/에뮬레이터가 필요합니다. SDK와 서명 설정은 대상 환경에서 확인합니다.

```bash
git clone git@github-personal:godekd3133/kbo-fans.git
cd kbo-fans
```

`github-personal`은 로컬 SSH 별칭입니다. 별칭이 없는 환경에서는 GitHub Clone 메뉴의 HTTPS/SSH 주소를 사용합니다.

## 백엔드 실행

저장소 루트에서 다음 명령을 실행합니다.

```bash
cd backend
python3 -m venv .venv
source .venv/bin/activate
pip install -e ".[dev]"
uvicorn kbo_fans_backend.main:app --reload --host 0.0.0.0 --port 8000
```

별도 터미널에서 API 기본 상태를 확인합니다.

```bash
curl http://localhost:8000/api/health
```

`0.0.0.0` 바인딩은 같은 네트워크의 실기기가 접속할 때 필요합니다. 로컬 브라우저만 사용하면 기본 localhost 바인딩으로 실행할 수 있습니다. 환경 변수는 `backend/.env.example`을 기준으로 준비하며 실제 비밀값은 커밋하지 않습니다.

## 앱 실행

직접 Flutter를 실행하는 경우 `app/`에서 실행합니다.

```bash
cd app
flutter pub get
flutter run -d chrome \
  --dart-define=APP_ENV=local \
  --dart-define=USE_BACKEND_API=true \
  --dart-define=API_BASE_URL=http://localhost:8000/api
```

저장소 루트의 공용 진입점도 사용할 수 있습니다.

```bash
./scripts/codex-run.sh doctor
./scripts/codex-run-web-dev.sh
./scripts/codex-run-ios.sh
./scripts/codex-run-android.sh
```

정적 Web 프리뷰는 `./scripts/codex-run-web.sh`이며 release Web 빌드 후 로컬 서버를 띄웁니다. Codex 실행 액션은 스크립트를 앱 UI에 수동 등록해야 합니다.

## 기기별 API 주소

| 환경 | 로컬 백엔드 주소 예시 |
| --- | --- |
| 같은 Mac의 브라우저 / iOS 시뮬레이터 | `http://localhost:8000/api` |
| Android 기본 에뮬레이터 | `http://10.0.2.2:8000/api` |
| iPhone / Android 실기기 | `http://<개발-Mac-LAN-IP>:8000/api` |

```bash
API_BASE_URL=http://<개발-Mac-LAN-IP>:8000/api ./scripts/codex-run-ios.sh
API_BASE_URL=http://10.0.2.2:8000/api ./scripts/codex-run-android.sh
```

실기기의 `localhost`는 그 기기 자체입니다. 앱·서버가 같은 네트워크에 있어야 하며 API 주소는 `/api`를 포함합니다. 일반 실행은 항상 backend API 모드를 유지합니다. `USE_BACKEND_API=false`는 의도적인 direct KBO 파서 비교 세션에서만 사용합니다.

## 상세 문서와 소스

- [실행 가이드](https://github.com/godekd3133/kbo-fans/blob/main/README.md)
- [백엔드 실행](https://github.com/godekd3133/kbo-fans/blob/main/backend/README.md)
- [공용 실행 스크립트](https://github.com/godekd3133/kbo-fans/blob/main/scripts/codex-run.sh)
- [환경 변수 예시](https://github.com/godekd3133/kbo-fans/blob/main/backend/.env.example)
