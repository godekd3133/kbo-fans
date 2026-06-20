# Release API Backend TODO

> 작성일: 2026-05-20

## 현재 결론

- production API는 현재 AWS ECS/Fargate smoke endpoint `http://kbo-fans-api-469252833.us-east-1.elb.amazonaws.com/api`를 release/tester 검증에 사용한다.
- `APP_ENV=release` 빌드는 화면 데이터, push registration, Live Activity token 등록 모두 `RELEASE_API_BASE_URL` 로 지정한 실제 운영 API가 필요하다.
- artifact 생성 전후에는 backend API health gate와 push readiness를 분리해서 확인한다.
- API 미구현 영역은 release artifact에 숨기지 않고 backend route/snapshot 계약을 먼저 보강한다. direct KBO는 `USE_BACKEND_API=false` parser/debug 세션에서만 사용한다.

## 해야 할 일

1. 운영 API 배포 대상 결정
   - AWS ECS/Fargate, EC2, Render, Fly.io, Railway, 또는 사내 서버 중 하나 선택
   - FastAPI 앱 `backend/src/kbo_fans_backend/main.py` 를 ASGI 서버로 실행할 수 있어야 함
   - 노트북 없이 push / Live Activity를 시연할 때는 `infra/aws/ecs-fargate/`의 API service + sync worker service 템플릿을 우선 사용

2. 운영 도메인 결정
   - 권장: `api.kbofans.com`
   - DNS A/CNAME 레코드를 실제 배포 대상에 연결

3. HTTPS/TLS 설정
   - `https://api.kbofans.com` 인증서 발급
   - 앱 release 빌드는 HTTPS API만 정상 운영 대상으로 봄

4. 환경 변수/시크릿 설정
   - KBO 로그인 또는 protected relay가 필요하면 운영 서버 시크릿으로만 주입
   - repo 문서나 코드에 plaintext credential 기록 금지
   - snapshot 저장 경로, cache TTL, CORS 허용 origin 확인
   - 앱 종료 후 push / Live Activity 시연이 필요하면 `docs/PUSH_LIVE_ACTIVITY_BACKEND_SETUP.md` 기준으로 Firebase Admin, APNs Auth Key, `PUSH_SYNC_SECRET`도 같이 설정
   - AWS ECS/Fargate에서는 Secrets Manager 값을 `FIREBASE_SERVICE_ACCOUNT_JSON`, `APNS_AUTH_KEY_P8`, `PUSH_SYNC_SECRET` 환경변수로 주입

5. release health endpoint 통과
   - `GET /api/health`
   - `GET /api/scoreboard/home`
   - `GET /api/home`
   - `GET /api/schedule`
   - `GET /api/standings`
   - `GET /api/records/overview`

6. GitHub Actions 연결
   - GitHub Actions variable 또는 secret에 `RELEASE_API_BASE_URL=https://api.kbofans.com/api` 등록
   - 기본 도메인이 다르면 workflow 입력 `release_api_base_url` 로 실제 주소 입력
   - release artifact metadata의 `push_api_base_url`이 의도한 운영 API인지 확인

## 완료 기준

- `PUSH_SYNC_SECRET=<...> ./scripts/codex-run.sh push-readiness` 통과
- Android/iOS/Web `APP_ENV=release` 빌드가 backend API data mode와 운영 `API_BASE_URL`을 함께 포함해 생성됨
- 실기기 release 설치 후 홈/일정/순위/기록실은 backend API 기준으로 로딩되고, push / Live Activity token registration도 production API 기준으로 성공함
- 노트북이 꺼진 상태에서도 push / Live Activity를 시연하려면 운영 backend의 sync worker 또는 `/api/push/live-activity/sync-scoreboard` trigger가 5초 간격으로 실행됨
