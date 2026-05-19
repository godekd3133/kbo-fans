# Release API Backend TODO

> 작성일: 2026-05-20

## 현재 결론

- 현재 production API 도메인은 확정되지 않았다.
- `APP_ENV=release` 빌드는 `https://api.kbofans.com/api` 또는 `RELEASE_API_BASE_URL` 로 지정한 실제 운영 API가 필요하다.
- 운영 API가 없으면 release health gate가 빌드/배포를 막는 것이 맞다.
- API 미구현 영역의 iPhone release-mode 검증은 release API가 아니라 `APP_ENV=local + PREFER_DIRECT_SCRAPE=true` 임시 direct-primary 빌드로 진행한다.

## 해야 할 일

1. 운영 API 배포 대상 결정
   - AWS ECS/Fargate, EC2, Render, Fly.io, Railway, 또는 사내 서버 중 하나 선택
   - FastAPI 앱 `backend/src/kbo_fans_backend/main.py` 를 ASGI 서버로 실행할 수 있어야 함

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

## 완료 기준

- `scripts/release-api-health-check.sh https://api.kbofans.com/api` 통과
- Android/iOS/Web `APP_ENV=release` 빌드가 API health gate 이후 생성됨
- 실기기 release 설치 후 홈/일정/순위/기록실이 production API 기준으로 로딩됨
