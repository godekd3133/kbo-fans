# 원격 푸시 작업 보관 메모

최종 업데이트: 2026-06-04

## 현재 사용 기준

이 문서는 2026-03-31 기준 원격 푸시 재개 메모를 보관하기 위한 문서다. 현재 작업 기준은 아래 문서를 우선한다.

- `docs/PUSH_LIVE_ACTIVITY_BACKEND_SETUP.md`
- `./scripts/push-demo-setup-status.sh --env-file /tmp/kbo-fans-aws.env --repo godekd3133/kbo-fans`
- `./scripts/push-demo-readiness-audit.sh --env-file /tmp/kbo-fans-aws.env --repo godekd3133/kbo-fans`
- `./scripts/push-live-preflight.sh --env-file /tmp/kbo-fans-aws.env --aws`

2026-06-04 검증 기준으로 앱 쪽 Firebase/APNs/Live Activity 프로젝트 파일은 `./scripts/push-live-preflight.sh --app-only`에서 통과했다. 현재 시연을 막는 항목은 코드 연결 부재가 아니라 Firebase Admin JSON, Apple APNs `.p8`, AWS deploy target, GitHub Actions secrets/variables 같은 운영 입력값 미설정이다.

앱 종료 후에도 Dynamic Island / Live Activity가 갱신되려면 앱의 direct KBO data path만으로는 부족하다. 운영 backend가 KBO 상태를 polling하고 저장된 FCM / ActivityKit token으로 FCM/APNs push를 보내야 한다.

## 현재 상태

아래 내용은 2026-03-31 기준 보관 내용이다. 최신 상태를 판단할 때는 위의 현재 사용 기준을 우선한다.

원격 푸시가 "코드 경로상으로는" 연결되어 있음.

- 앱
  - Firebase 초기화 서비스 추가
  - FCM 토큰/토픽 동기화 서비스 추가
  - 마이팀 변경 시 토픽 재동기화 연결
  - 설정 화면 알림 토글과 푸시 설정 저장 연결
  - Android 13 `POST_NOTIFICATIONS` 권한 선언 추가
  - 진단 화면에 push 상태 표시 추가
- 백엔드
  - `/api/push/register` 유지
  - `/api/push/test` 테스트 발송 endpoint 추가
  - Firebase Admin 기반 발송 서비스 추가
  - `FIREBASE_SERVICE_ACCOUNT_PATH`, `FIREBASE_PROJECT_ID` 설정값 추가

## 2026-03-31 기준 막힌 이유

실제 Firebase 설정 파일이 없음.

- 앱에 없음
  - `app/android/app/google-services.json`
  - `app/ios/Runner/GoogleService-Info.plist`
- 백엔드에 없음
  - Firebase 서비스 계정 JSON
- 로컬 환경에도 없음
  - gcloud/firebase 기본 자격 파일 미존재 확인

따라서 현재 로그의

- `Push init skipped: [core/not-initialized] ...`

는 코드 문제가 아니라 Firebase 설정 파일 부재로 인한 정상 경고임.

## 관련 코드 위치

### 앱

- `/Users/kimminkyu/Bagelcode/Repository_Bagelcode/kbo_fans/app/lib/services/push_notification_service.dart`
- `/Users/kimminkyu/Bagelcode/Repository_Bagelcode/kbo_fans/app/lib/main.dart`
- `/Users/kimminkyu/Bagelcode/Repository_Bagelcode/kbo_fans/app/lib/data/providers.dart`
- `/Users/kimminkyu/Bagelcode/Repository_Bagelcode/kbo_fans/app/lib/features/settings/settings_screen.dart`
- `/Users/kimminkyu/Bagelcode/Repository_Bagelcode/kbo_fans/app/lib/features/settings/api_diagnostics_screen.dart`
- `/Users/kimminkyu/Bagelcode/Repository_Bagelcode/kbo_fans/app/android/app/src/main/AndroidManifest.xml`

### 백엔드

- `/Users/kimminkyu/Bagelcode/Repository_Bagelcode/kbo_fans/backend/src/kbo_fans_backend/services/push.py`
- `/Users/kimminkyu/Bagelcode/Repository_Bagelcode/kbo_fans/backend/src/kbo_fans_backend/api/routes/push.py`
- `/Users/kimminkyu/Bagelcode/Repository_Bagelcode/kbo_fans/backend/src/kbo_fans_backend/core/config.py`
- `/Users/kimminkyu/Bagelcode/Repository_Bagelcode/kbo_fans/backend/.env.example`
- `/Users/kimminkyu/Bagelcode/Repository_Bagelcode/kbo_fans/backend/README.md`

## 재개 시 필요한 파일

### 앱

Android:

- `google-services.json`
  - 넣을 위치:
    `/Users/kimminkyu/Bagelcode/Repository_Bagelcode/kbo_fans/app/android/app/google-services.json`

iOS:

- `GoogleService-Info.plist`
  - 넣을 위치:
    `/Users/kimminkyu/Bagelcode/Repository_Bagelcode/kbo_fans/app/ios/Runner/GoogleService-Info.plist`

### 백엔드

- Firebase Admin 서비스 계정 JSON
  - 권장 위치:
    `/Users/kimminkyu/Bagelcode/Repository_Bagelcode/kbo_fans/backend/firebase-service-account.json`

그리고 backend `.env`에 아래 추가:

```env
FIREBASE_SERVICE_ACCOUNT_PATH=/Users/kimminkyu/Bagelcode/Repository_Bagelcode/kbo_fans/backend/firebase-service-account.json
FIREBASE_PROJECT_ID=YOUR_FIREBASE_PROJECT_ID
```

## 재개 순서

1. 앱 Firebase 설정 파일 2개 배치
2. 백엔드 서비스 계정 JSON 배치
3. backend `.env`에 Firebase 경로/프로젝트 ID 설정
4. `cd backend && source .venv/bin/activate && pip install -e ".[dev]"` 재실행
5. 앱 실행 후 설정 > 연결 진단에서 push 상태 확인
6. 백엔드 테스트 발송 실행

```bash
curl -X POST http://127.0.0.1:8000/api/push/test \
  -H 'Content-Type: application/json' \
  -d '{
    "title": "KBO Fans Test",
    "body": "Push delivery test",
    "topic": "game_start_LG"
  }'
```

7. 실제 단말에서 수신 확인

## 참고

- 현재 메트릭 경고(`client metric send failed`)는 이미 정리됨.
- 전체 backend 테스트는 여전히 기존 `tests/test_relay_service.py` 2건 실패가 남아 있을 수 있으므로, 푸시 재개 시에는 push 관련 확인만 분리해서 보는 게 안전함.
