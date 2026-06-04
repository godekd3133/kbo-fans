# Changelog

이 문서는 사용자 입장에서 의미 있는 저장소 변경 사항을 기록합니다.

형식 원칙:

- 날짜 기준 역순 기록
- 사용자에게 보이는 기능/구조 변화 위주 기록
- 세부 작업 로그는 `docs/WORKLOG.md`에서 관리

## [Unreleased]

### Added

- 앱 종료 후 일반 푸시와 iOS Live Activity / Dynamic Island를 갱신할 수 있도록 ActivityKit push token 등록, backend token registry, APNs liveactivity 발송 경로를 추가
- 운영 백엔드가 scoreboard를 읽어 등록된 Live Activity 세션에는 update/end payload를 보내고, score diff 기반 일반 FCM moment push도 발행할 수 있는 sync trigger를 추가
- Firebase/APNs/registry/scheduler secret 설정 누락을 확인하는 backend push config diagnostics API/CLI를 추가
- 배포 후 `/health`와 push readiness를 한 번에 확인하는 `scripts/push-readiness-check.sh`를 추가
- AWS ECS/Fargate에서 API service와 long-running sync worker를 나눠 배포할 수 있는 템플릿을 추가
- Firebase Admin JSON, APNs `.p8`, push sync secret을 AWS Secrets Manager에 생성/갱신하는 배포 보조 스크립트를 추가
- backend Docker image를 ECR에 build/tag/push하고 `CONTAINER_IMAGE_URI` export를 생성하는 배포 보조 스크립트를 추가
- AWS ECS task definition placeholder를 환경변수 기반으로 렌더링/검증하는 배포 보조 스크립트를 추가
- AWS push 배포 전 env, rendered JSON, secret, IAM role, ECR, EFS, CloudWatch log group을 점검하는 사전점검 스크립트를 추가
- ALB, ECS Fargate API service, scoreboard sync worker, EFS registry, IAM, CloudWatch log group을 만드는 CloudFormation stack 템플릿과 배포 스크립트를 추가
- CloudFormation stack output의 `ApiBaseUrl`을 release build용 `RELEASE_API_BASE_URL` / `API_BASE_URL` env로 추출하는 스크립트를 추가
- secret upload, ECR image push, CloudFormation deploy, stack output export, readiness를 순서대로 실행하는 AWS push demo 통합 배포 스크립트를 추가
- 배포 전 Firebase client 파일, APNs/Live Activity capability, backend secret env, AWS env 형태를 확인하는 Push / Live Activity preflight 스크립트를 추가
- 로컬 AWS CLI credential과 Docker daemon 상태를 확인하는 tooling check 스크립트와, GitHub Actions에서 push demo deploy를 수동 실행하는 workflow를 추가
- 로컬 env 파일과 Firebase client config 파일을 기준으로 GitHub Actions push deploy secrets/variables를 dry-run 또는 실제 업로드할 수 있는 `gh` CLI 보조 스크립트를 추가
- GitHub Actions `Push Demo Deploy` workflow를 CLI에서 dispatch하고, 원격 workflow 미등록 상태를 명확히 안내하는 보조 스크립트를 추가
- GitHub Actions `Push Demo Deploy` dispatch 전에 필수 secrets/variables 누락을 로컬에서 확인하는 사전검사를 추가
- push demo env checklist를 GitHub Actions secrets/variables 업로드까지 포함하도록 보강하고, obvious placeholder 값 업로드를 차단
- 앱 종료 후 push / Live Activity 시연 준비 상태를 앱 파일, env, GitHub Actions, 로컬 tooling 기준으로 감사하는 스크립트를 추가
- push demo env 초안 생성, GitHub Actions OIDC role dry-run, readiness audit, 다음 명령 안내를 한 번에 실행하는 setup status 스크립트를 추가
- push demo env 초안 생성 시 repo 인자를 받아 후속 OIDC/audit 명령에 실제 GitHub repo를 표시하도록 개선
- push demo env 초안과 AWS deploy env example에 Firebase/Admin/APNs/AWS 값의 발급 위치와 GitHub 업로드 대상 주석을 추가
- push demo setup status 출력에 Firebase/Apple/AWS/GitHub에서 가져올 값과 env/GitHub/AWS 반영 위치를 정리한 Required Values checklist를 추가
- Push / Live Activity preflight가 release 빌드/CI의 `API_BASE_URL` token-registration handoff까지 확인하도록 보강
- GitHub Actions push demo dispatch 사전검사 실패 시 secrets 업로드 복구 명령에 실제 GitHub repo를 표시하도록 개선
- GitHub Actions가 장기 AWS access key 없이 push demo backend를 배포할 수 있도록 `AWS_ROLE_TO_ASSUME` OIDC role 생성 스크립트와 CloudFormation 템플릿을 추가
- AWS Secrets Manager 값을 `FIREBASE_SERVICE_ACCOUNT_JSON`, `APNS_AUTH_KEY_P8` env로 주입해 FCM/APNs를 설정할 수 있도록 backend secret 입력 방식을 보강
- 운영 중 scoreboard sync worker 실행 여부를 확인할 수 있도록 push config diagnostics에 scheduler heartbeat를 추가

### Changed

- 앱/웹/릴리즈/CI artifact 기본 데이터 경로를 backend API 없이 direct KBO + 허용된 snapshot 경로로 전환
- GitHub Actions `App Build Artifacts` workflow의 signing/config/metadata 파일 생성을 runner 들여쓰기와 무관하게 동작하도록 보강
- 오래된 원격 푸시 보관 메모가 현재 Firebase/Admin/APNs/AWS 설정 상태와 충돌하지 않도록 최신 Push / Live Activity backend setup 기준으로 안내를 보정
- Backend API 사용은 `USE_BACKEND_API=true` 명시 opt-in 경로로 분리
- Release direct 빌드는 데이터 경로를 no-backend로 유지하면서 push / Live Activity token 등록용 운영 `API_BASE_URL`을 함께 주입하도록 보강
- 웹 기록실/선수 direct 조회가 KBO source를 CORS proxy 경로로 접근하도록 보강
- Android `home_widget`의 Glance 동적 의존성이 최신 alpha를 잡아 SDK/AGP 요구사항을 끌어올리지 않도록 Glance 안정 버전 고정
- Live Activity scoreboard sync와 push readiness one-shot sync 기본 날짜를 AWS UTC가 아닌 KBO 경기일(`Asia/Seoul`) 기준으로 계산하도록 변경
- Push readiness check가 scheduler heartbeat 최신성을 확인해 sync worker가 멈춘 배포를 통과시키지 않도록 변경
- Push token registry가 파일락과 atomic write를 사용해 API service와 sync worker의 동시 저장 중 token / heartbeat 갱신을 잃지 않도록 변경

## [0.0.29] - 2026-06-04

### Fixed

- 일정 화면에서 다음 달/이전 달로 이동한 뒤 선택된 `일정` 하단 탭을 다시 누르면 현재 달로 초기화되던 경로 차단
- 일정 월 데이터가 실패한 상태에서도 캘린더와 월 이동 컨트롤은 유지되도록 보정
- KBO 취소 사유가 `우천취소`로 내려오는 경우 일정/홈/상세/위젯 상태 문구에 우천취소 라벨을 표시
- 문자중계에서 포일 이벤트가 일반 플레이 배지로 보이던 분류를 포일 표기로 보정
- 롯데 자이언츠 팀 로고가 흰 사각 배경과 함께 보이던 CDN 이미지 경로를 투명 배경 경로로 보정
- API를 쓰지 않는 direct-primary 문자중계 빌드에서 현재 타석 선수 이미지가 비어 글자 fallback으로 보일 수 있던 경로 보정
- API를 쓰지 않는 direct-primary 박스스코어/라인업에서 영문 선수목록 이름과 한글 경기 원본 이름이 매칭되지 않아 선수 이미지가 빠질 수 있던 경로 보정
- direct-primary 문자중계 요약 fallback이 예정 경기에서도 1회초/1회말 skeleton을 만들어 실제 중계처럼 보일 수 있던 경로 차단

## [0.0.28] - 2026-05-20

### Fixed

- LIVE/당일 박스스코어가 비어 있을 때 같은 팀 조합의 전날 경기 박스스코어를 대체 데이터로 붙일 수 있던 경로 차단
- 기록실 overview 리더보드가 KBO 응답 row 순서 흔들림으로 1위가 아닌 항목부터 내려와 첫 화면이 오류 상태로 보일 수 있던 경로 차단

## [0.0.27] - 2026-05-20

### Fixed

- LIVE 홈/위젯 요약 스코어보드에서 schedule payload의 0:0 값이 KBO main list의 실제 득점 갱신을 막아 진행 중 경기가 0:0으로 남을 수 있던 경로 보정

## [0.0.26] - 2026-05-20

### Changed

- backend current data routes가 공통 runtime service singleton을 공유하도록 정리해 `/scoreboard/home` 직후 `/home` 또는 game detail 계열 호출에서 같은 TTL 캐시를 재사용하도록 변경
- 홈 화면 secondary `/home` aggregate provider 구독을 scoreboard 첫 데이터 프레임 이후로 지연해 첫 화면 렌더 전에 부가 API가 시작되지 않도록 변경
- 홈 자동 refresh timer가 unrelated rebuild 때마다 재시작되지 않도록 scoreboard signature 기반으로 안정화

### Fixed

- 홈 로딩 스켈레톤의 작은 카드가 모바일/테스트 뷰포트에서 overflow 될 수 있던 간격 보정

## [0.0.25] - 2026-05-20

### Changed

- 앱 `Game` 모델에 팀별 H/E/B 통계 존재 여부를 보존하는 `hasStats` 플래그 추가
- 스코어 탭과 문자중계 요약에서 H/E/B 원천값이 없으면 `0` 대신 `-`로 표시
- 홈 마이팀 경기 카드에서 양 팀 H/E/B가 확인되지 않은 경우 해당 요약 행을 숨기도록 변경
- KBO 브리프의 `안타 공방` 후보는 양 팀 안타/실책/사사구 통계가 실제로 내려온 경기만 사용하도록 변경

### Fixed

- 홈/상세/중계 화면이 결측 team totals를 `0안타`, `0실책`, `0볼넷`처럼 확정 통계로 오인하게 만들 수 있던 표시 경로 차단

## [0.0.24] - 2026-05-20

### Changed

- backend `/scoreboard/home`과 `/scoreboard/compact`가 홈/위젯 표면에 필요한 schedule + main list 기반 요약만 만들도록 변경해 경기별 상세 스코어보드 크롤링을 첫 로딩 경로에서 제거
- full `/scoreboard`와 `/game/{gameId}` 경로는 기존처럼 상세 스코어보드 크롤러와 View1 보강을 유지
- current `/scoreboard/home`도 원천 실패 시 fresh snapshot으로 정상 응답을 만들지 않도록 회귀 테스트 추가

### Fixed

- 홈 첫 로딩과 compact/widget 갱신이 경기 수만큼 상세 스코어보드 원천 호출을 늘릴 수 있던 fan-out 경로 차단

## [0.0.23] - 2026-05-20

### Changed

- GitHub Actions app artifact workflow가 Android/Web/iOS 빌드 전에 backend pytest를 먼저 실행하도록 변경
- backend 현재 시즌 팀 선수, 팀 스탯, 선수 상세 API가 crawler 실패 시 fresh/stale snapshot이나 stale in-memory cache로 정상 응답을 만들지 않도록 변경
- 과거 시즌 팀 선수, 팀 스탯, 선수 상세는 기존처럼 저장 snapshot 우선 및 crawler 실패 fallback 정책 유지

### Fixed

- 현재 시즌 기록실 팀/선수 화면이 원천 조회 실패 상태인데도 저장 snapshot 때문에 최신 데이터처럼 보일 수 있던 경로 차단

## [0.0.22] - 2026-05-20

### Changed

- 현재 날짜 스코어보드, 홈 aggregate, 경기 상세, 문자중계, 박스스코어, 라인업, 현재 월 일정, 현재 시즌 순위/기록실/팀 기록은 API 실패 시 TTL 안의 로컬 API cache를 정상 데이터처럼 재사용하지 않도록 변경
- backend 현재 스코어보드, 일정, 순위, 기록실 요약, 리더보드도 crawler 실패 시 fresh snapshot을 정상 응답처럼 반환하지 않도록 변경
- 홈 첫 로딩에서 오늘 스코어보드 별도 로컬 cache를 먼저 렌더링하던 경로 제거
- 과거 날짜/시즌/월 조회만 기존 cached-first 또는 snapshot fallback 정책을 유지해 히스토리 화면의 빠른 조회는 보존
- 2026-05-20 취소 경기와 현재 순위/기록실 snapshot 저장 시각을 최신 수집본 기준으로 갱신

### Fixed

- 서버/API가 죽었는데 웹/앱에 남은 fresh API cache 때문에 현재 경기나 현재 기록이 최신 정보처럼 보일 수 있던 masking 경로 차단
- backend 현재 데이터 crawler 실패가 current snapshot으로 숨겨질 수 있던 경로 차단

## [0.0.21] - 2026-05-20

### Changed

- 앱 공통 `ApiClient.getCached`에 payload validator를 추가해 캐시를 읽거나 새로 저장하기 전에 malformed 응답을 차단
- records overview API cache key를 `v4`, leaderboard API cache key를 `v3`로 올려 웹/앱에 남은 구형 기록실 캐시를 무효화
- 앱 전역 Riverpod retry를 비활성화해 API 실패가 반복 재시도 뒤에 숨지 않고 화면 오류 상태로 바로 전달되도록 변경
- backend 2013 타율 리더보드 snapshot과 records overview featured 카드를 시즌 공식 리더 기준으로 보강

### Fixed

- 기록실 웹/API cache에 남은 1위 누락 리더보드가 2013 타율처럼 다시 표시될 수 있던 경로 차단
- 2013 타율 리더보드 fallback이 이병규 1위부터 시작하지 못하던 snapshot 누락 보강
- 기록실 리그 요약 실패가 빈 공간처럼 숨겨지던 화면을 오류 카드와 다시 시도 버튼으로 노출하도록 보강
- 팀 기록실 오류 상태에 사용자용 실패 문구를 표시하고 refresh 실패는 Dev Console에 기록하도록 정리

## [0.0.20] - 2026-05-20

### Changed

- backend `/home` aggregate는 현재/미래 날짜에서 schedule, standings, records overview 하위 호출 실패를 빈 섹션/placeholder로 조용히 대체하지 않도록 변경
- 과거 날짜 `/home` aggregate만 기존 partial fallback을 유지해 히스토리 조회 안정성은 보존
- records overview crawler와 2011 snapshot의 featured 카드를 canonical 시즌 리더 기준으로 정리하고 회귀 테스트 추가
- runtime data 정책 문서와 skill에 home aggregate current-date fail-fast 기준 추가

### Fixed

- 홈 첫 화면에서 현재 데이터 일부가 실패했는데도 `오늘 경기 없음`, 빈 순위, 빈 기록 카드처럼 정상 상태로 오해될 수 있던 경로 차단
- records overview snapshot 재생성 시 OPS 하위권 선수가 `시즌 OPS 리더`로 노출될 수 있던 데이터 생성 경로 차단
- 기록실 디바이스 snapshot에 남은 구형 `recordsOverview` 캐시가 1위가 누락된 리더보드를 계속 표시할 수 있던 경로 차단
- records overview / leaderboard device snapshot은 핵심 리더보드가 1위부터 시작할 때만 저장/재사용하도록 보강

## [0.0.19] - 2026-05-20

### Changed

- 현재/진행 예정 경기의 박스스코어와 라인업은 과거 snapshot을 실패 fallback으로 쓰지 않고 최신 원천 실패를 그대로 노출하도록 변경
- LIVE 경기 문자중계는 crawler 실패 시 요약/과거 snapshot으로 조용히 대체하지 않고 실패를 전파하도록 변경
- 팀 기록 API는 선수 목록이나 팀 스탯 중 한쪽 실패를 빈 payload로 숨기지 않고 API 실패로 처리하도록 변경
- `./scripts/codex-run.sh web` 기본 실행을 release API health gate를 통과한 static web release 경로로 변경
- Chrome debug 세션용 실행 경로를 `./scripts/codex-run.sh web-dev`와 `scripts/codex-run-web-dev.sh`로 분리
- README, APP_SPEC, 릴리즈 문서를 current/live failure masking guard와 web 기본 실행, web-dev, web-release 역할 기준으로 정리

### Fixed

- 현재 경기 상세/라인업/중계가 오래된 snapshot 또는 요약 fallback으로 정상 데이터처럼 보일 수 있던 경로 차단
- 팀 기록에서 부분 실패가 빈 선수 목록이나 빈 팀 스탯처럼 표시되어 데이터가 없는 것처럼 오해될 수 있던 경로 차단
- release API DNS/TLS/API health gate를 거치지 않은 웹 기본 실행 명령으로 release 검증을 착각할 수 있던 경로 차단

## [0.0.18] - 2026-05-20

### Changed

- backend historical leaderboard snapshot에 2011 ERA, 2013 HR 저장본을 추가해 원천 조회 실패 시에도 대표 과거 리더보드가 복구되도록 보강
- 2011 ERA 1위 `윤석민 2.45`, 2013 HR 1위 `박병호 37`처럼 은퇴 선수가 포함된 snapshot 상위 리더를 회귀 테스트로 고정
- Codex 웹 wrapper를 release API health gate 경로로 맞추고, Android/Web release 전용 wrapper를 추가

### Fixed

- 2011 ERA, 2013 HR 단건 리더보드 endpoint가 원천 조회 실패 시 snapshot fallback 없이 비어 있거나 실패할 수 있던 경로 보강

## [0.0.17] - 2026-05-20

### Changed

- 앱/홈 aggregate/widget background의 direct KBO 라우팅을 `APP_ENV=local`, 네이티브 런타임, `API_BASE_URL` 미지정, `PREFER_DIRECT_SCRAPE=true` 조건을 모두 만족할 때만 허용하도록 통일
- provider routing 회귀 테스트를 추가해 웹, release, API override 빌드가 direct KBO 경로로 빠지지 않도록 검증
- local backend 없이 검증하는 `android-release`, `web-release` 실행 경로를 추가하고 release API health gate 통과 URL만 주입하도록 정리
- 일반 API-backed 앱 모드에서는 현재 시즌 순위/기록실 요약/리더보드 API 실패를 앱 번들 bootstrap으로 대체하지 않도록 변경
- device records overview snapshot은 AVG/HR/OPS/ERA가 모두 있는 완성본만 저장/재사용하도록 제한

### Fixed

- `PREFER_DIRECT_SCRAPE=true` 하나만으로 API override가 있는 local native나 widget background 경로가 direct KBO를 선택할 수 있던 위험 차단
- 기본 운영 API 도메인이 DNS/TLS/API health gate를 통과하지 못하면 release 실행/빌드가 시작되지 않도록 로컬 실행 경로까지 차단
- 원격 API가 없는 상황에서 현재 시즌 순위/기록실 요약/리더보드가 앱 번들 데이터로 조용히 표시될 수 있던 경로 차단
- 불완전한 records overview 응답이 device snapshot으로 저장되어 이후 기록실 첫 화면을 부분 데이터로 오염시킬 수 있던 경로 차단

## [0.0.16] - 2026-05-20

### Changed

- backend 현재 날짜 스코어보드와 현재 시즌/월 일정/순위/기록실 요약/리더보드 snapshot fallback도 `savedAt` 기준 6시간 이내 저장본만 사용하도록 제한
- 과거 날짜/시즌/월 스코어보드, 일정, 순위, 기록실 snapshot은 기존처럼 저장본 우선 fallback을 유지하도록 current 데이터 freshness와 분리
- 현재 날짜 scoreboard snapshot fallback은 fresh + terminal 상태일 때만 허용해 진행 중 경기의 오래된 snapshot 재노출을 차단
- 앱 기록실 선수/리더 모델과 device/local snapshot 직렬화에서 `isRetired` 플래그를 보존하도록 변경
- 앱 API cached-first 요청은 원격 실패 시에도 TTL이 지난 cache를 fallback으로 반환하지 않도록 제한
- 현재 시즌 records overview 번들은 `generatedAt` 기준 최신 snapshot만 fallback으로 사용하도록 제한
- 홈 스코어보드 로컬 cache는 `savedAt` 포함 payload만 인정하고 경기 상태별 TTL을 적용하도록 변경
- 현재 시즌 팀 선수 API 요청은 오래된 cache 우선 표시를 피하고 원격 최신값을 먼저 시도하도록 변경

### Fixed

- 원천 조회 실패 시 오래된 현재 날짜/시즌 backend snapshot이 최신 데이터처럼 재노출될 수 있던 경로 차단
- 과거 시즌 기록실 리더보드가 은퇴 선수를 누락해 `2, 9, 13위`처럼 보이거나 2011 ERA가 빈 데이터로 표시되던 문제를 수정
- 앱 재실행 직후 오래된 홈 스코어보드 로컬 cache가 최신 현재 경기처럼 먼저 보일 수 있던 경로 차단

## [0.0.15] - 2026-05-20

### Changed

- 순위 번들 fallback도 exact-season-only 정책으로 고정하고, 현재 시즌 순위는 6시간 이내 생성본만 사용하도록 제한
- bootstrap snapshot 생성 스크립트가 live API를 여러 시즌에 팬아웃하지 않고, backend 저장 snapshot만 앱 번들로 동기화하도록 변경
- 웹 `APP_ENV=local` 빌드가 명시적 `API_BASE_URL` 없이 `localhost`를 보지 않고 운영 API 기본값을 사용하도록 변경
- 2009~2013, 2020 기록실 요약 backend snapshot을 실제 시즌 리더 데이터로 보강
- KT 2026 팀 선수/팀 스탯 번들 snapshot을 최신 backend snapshot 기준으로 갱신

### Fixed

- 2026 시즌 초반 2경기 기준 순위가 2001~2025 시즌까지 반복되어 보일 수 있던 번들 데이터 제거

## [0.0.14] - 2026-05-20

### Changed

- 앱 기기 snapshot 저장 형식을 `savedAt` + `payload` envelope로 감싸 현재 시즌 기록실 캐시 신선도를 판정할 수 있도록 변경
- 현재 시즌 팀 선수/팀 스탯/팀 기록/리더보드 기기 snapshot은 6시간 이내 저장본만 fallback으로 사용하도록 제한
- 현재 시즌 번들 팀 선수/팀 스탯 asset도 `savedAt` 기준 6시간 이내가 아니면 빈 상태로 처리해 오래된 2026 기록이 재노출되지 않도록 변경

### Fixed

- `savedAt`이 없는 구형 기기 snapshot이 현재 시즌 기록실에 남아 있을 때 오래된 팀 기록을 다시 보여줄 수 있던 경로 차단

## [0.0.13] - 2026-05-20

### Changed

- 구단 로고 URL을 KBO `fixed/emblem_*_L.png` 자산으로 교체해 온보딩, 홈, 일정, 상세, 순위의 로고 원본 해상도와 안정성을 개선
- 기록실 번들 overview fallback을 exact-season-only 정책으로 고정해 다른 시즌의 리더 데이터를 빌려 보여주지 않도록 변경
- 현재 시즌 팀 선수/팀 스탯은 저장 snapshot을 먼저 쓰지 않고 원천 조회를 우선하며, 실패 시에도 6시간 이내 snapshot만 fallback으로 사용하도록 보강
- backend 홈런 리더보드 2026 snapshot을 추가해 원천 조회가 느릴 때도 현재 시즌 홈런 순위 fallback을 사용할 수 있도록 보강
- KT 2026 팀 선수/팀 스탯 snapshot을 최신 원천 기준으로 갱신

### Fixed

- 번들 `records_overview.json`에 남아 있던 오래된 2026-03-31 기준 허경민/함덕주 등 잘못된 리더 데이터를 제거

## [0.0.12] - 2026-05-20

### Changed

- 기록실 첫 화면에서 미지원 `WAR` 카드 대신 `wRC+` 리더보드를 노출
- 라인업 탭 선발투수 카드의 박스 높이와 선수 사진 비율을 맞춰 빈 공간과 과도한 얼굴 확대를 줄이도록 조정
- 홈 마이팀 브리프 아래에 리그 전체 관전 포인트를 요약하는 `KBO 브리프` 카드 추가
- 경기 전 상태의 홈/일정 경기 표기는 점수 대신 `vs` 중심으로 보이도록 조정
- 경기 카드, 일정 카드, 기록실 카드/필터, 하단 탭, 온보딩 구단 카드에 짧은 press 피드백을 추가하고 점수 변경 모션을 더 부드럽게 개선
- 경기 상세의 회차/문자중계/박스스코어, 홈 보조 카드, 일정 달력, 설정 행에도 같은 micro motion을 확장 적용

### Fixed

- 2013년 등 과거 시즌 기록실 선수 이미지가 존재하지 않는 시즌별 CDN 폴더를 바라보던 문제를 수정
- 홈 `홈런왕` quick item이 선수 사진 대신 이름 첫 글자만 보이던 문제를 수정
- 종료/과거 경기의 박스스코어, 라인업, 문자중계가 완성된 저장 snapshot을 우선 사용해 불필요한 원천 재조회와 빈 상세 fallback을 줄이도록 수정
- 최근 3경기 흐름에 예정/취소/미완료 경기가 끼어들지 않도록 종료 경기만 집계

## [0.0.11] - 2026-05-20

### Changed

- 앱 버전을 `0.0.11+11`로 올리고 현재 테스트 가능한 릴리즈 기준을 `0.0.11`로 정리
- 과거 preview/prerelease 표기를 제거하고 GitHub 릴리즈, 앱 내 패치노트, 버전 정책을 `0.0.1`부터 이어지는 숫자 릴리즈 기준으로 재작성
- 라인업 탭 첫 진입에서 박스스코어 파생 타자/투수 fallback 조회를 제거해 `/game/{gameId}/lineup`과 양 팀 선수 이미지 조회만 사용하도록 축소
- 라인업 선발 비교에서 박스스코어가 없을 때 `0.00` 같은 가짜 수치 대신 `-`와 `선발 발표` 상태로 표시
- 홈 scoreboard 자동 refresh를 live 30초, scheduled 5분, terminal 정지로 조정
- 홈 스코어보드 캐시 payload가 같을 때 중복 저장과 불필요한 화면 갱신을 피하도록 보정
- 웹에서는 홈 위젯/Live Activity용 resume observer를 등록하지 않아 기록실/일정 복귀 시 전역 scoreboard refresh가 끼어들지 않도록 정리

## [0.0.10] - 2026-05-20

### Changed

- 임시 direct-primary iPhone 빌드에서 2025/2024 등 과거 시즌 기록실이 빈 결과로 보이던 문제를 수정
- KBO WebForms 세션 cookie와 전체 form state를 유지해 과거 시즌 records overview, leaderboard, team stats POST를 정상화
- 과거 시즌 팀 기록실은 현재 로스터 검색 대신 시즌/팀 필터가 걸린 KBO 기록 테이블에서 야수/투수 기록을 구성하도록 변경
- 앱 startup에서 원격 API prefetch 죽은 코드와 `startupScoreboardProvider` 의존성을 제거하고, 첫 route 진입은 local onboarding/my-team 상태만 확인하도록 정리
- backend records/team stats crawler도 동일한 WebForms payload 방식으로 보정해 snapshot 재생성 안정성을 개선

## [0.0.9] - 2026-05-20

### Changed

- 홈 화면에서 `/home` aggregate 로딩 중 별도 `recordsOverviewProvider`를 호출하던 보조 섹션 제거
- 홈 첫 화면 데이터 흐름을 `scoreboardProvider`와 지연 `homeAggregateProvider`로 고정
- aggregate 실패 시 schedule/standings/records 로컬 조립 fallback이 다시 실행되지 않도록 데이터 경로 문서와 구현 기준 정리
- direct-primary 정책 표현을 AGENTS/CLAUDE/엔지니어링 문서에 맞춰 동기화

## [0.0.8] - 2026-05-20

### Added

- 설정 화면에서 버전별 패치노트를 볼 수 있는 `패치노트` 진입점 추가
- 루트 `README.md` 추가
- 루트 `CHANGELOG.md` 추가
- GitHub Actions 수동 빌드 워크플로우 추가 (`.github/workflows/app-build-artifacts.yml`)
  - Android `apk` / `aab`
  - iOS simulator 앱 zip
  - 선택적 signed iOS `ipa`
  - Web 정적 빌드 zip
- Codex 앱 실행 액션용 `scripts/codex-run.sh` 추가
- 플랫폼 분리 Codex 실행 액션용 래퍼 스크립트 추가
  - `scripts/codex-run-ios.sh`
  - `scripts/codex-run-android.sh`
  - `scripts/codex-run-web.sh`
- 문서 유지관리 규칙에 `README.md`와 `CHANGELOG.md` 갱신 원칙 추가
- Flutter web 플랫폼 추가 (`app/web`)
- 하단 탭 `기록실` 추가
- 팀 엔트리 / 엔트리 제외 / 부상 상태와 간단 기록을 확인하는 선수 기록실 화면 추가
- 선수 프로필, 시즌 기록, 최근 기록을 보여주는 선수 상세 화면 추가
- 기록실에 `야수 / 투수` 탭과 `타율 / OPS / ERA / WHIP` 정렬 추가
- `/api/team/{teamId}/players`, `/api/player/{playerId}` 선수 API 추가
- 일정 화면에 경기별 예매처 / 예매 오픈 시간 표시 추가
- 경기 상세 화면에 예매처 바로가기와 예매 오픈 알림 설정 추가
- 경기 상세 화면에 KBO 공식 / 유튜브 하이라이트 카드와 웹 연결 추가
- 일정 구장별 보기에 구장 퀵링크 버튼을 추가해 원하는 구장 섹션으로 바로 이동할 수 있도록 개선
- web deep-link 라우터 회귀 테스트 추가
- Android release signing 예시 파일 추가 (`app/android/key.properties.example`)
- release 빌드 전 production API DNS/TLS/핵심 endpoint를 검증하는 health gate 스크립트와 GitHub Actions 차단 단계를 추가
- API 미구현 영역을 iPhone release-mode에서 검증할 수 있도록 임시 direct-primary `ios-local-release` / `codex-run-ios-local-release.sh` 경로 추가
- release API backend 준비 항목을 `docs/RELEASE_API_BACKEND_TODO.md`로 분리

### Changed

- 설정 화면의 `앱 밖 표면` 설명 블록을 제거하고, 장면별 알림 picker 안에서만 전달 방식을 고르도록 정리
- 홈, 일정, 순위, 기록실, 선수 상세의 로딩/데이터 전환과 주요 리스트 행 등장에 공통 모션을 적용해 화면 내부 변화도 부드럽게 보이도록 개선
- local native 실행에서 `API_BASE_URL`이 없을 때 dev API DNS 실패로 홈/일정/순위/기록실이 깨지지 않도록 실행 스크립트가 local backend URL을 주입하고, 실패 시 중단하도록 보정
- `ios-local-release`는 API 실패 fallback이 아니라 `PREFER_DIRECT_SCRAPE=true` 를 명시한 임시 direct-primary 경로로 분리
- 기록실 팀 선수 bootstrap asset을 2022~2026 전 구단으로 확장하고, 과거 시즌 팀 로스터는 현재 등록 선수 direct 검색 대신 snapshot을 사용하도록 보정
- 기록실 팀 스탯은 타격/투구가 모두 있는 complete snapshot만 앱에 포함하고, partial payload가 UI에 노출되지 않도록 보정
- 기록실 local asset fallback이 없는 시즌에서 다른 시즌 데이터를 빌려 보여주지 않도록 변경
- 임시 direct-primary iPhone 빌드에서 2025/2024 등 과거 시즌 기록실이 빈 결과로 보이던 문제를 수정. KBO WebForms 세션/form state를 유지하고, 과거 시즌 팀 기록은 시즌/팀 필터가 걸린 KBO 기록 테이블에서 직접 구성
- 홈 초기 로딩 화면에서 여러 카드가 각각 spinner를 보여 중복 로딩처럼 보이던 UI를 skeleton 중심으로 정리
- 설정 화면의 `버전` 항목이 하드코딩 값 대신 실제 앱 메타데이터 버전을 표시하도록 개선
- 설정의 앱 정보 및 지원 영역에서 이용약관, 개인정보처리방침, 오픈소스 라이선스, 문의하기가 실제로 열리도록 정리
- 홈/기록실의 홈런 관련 리더 표현을 팬에게 더 자연스러운 `홈런왕` 중심 카피로 정리
- v4 UX 평가 후 홈 대표 경기 CTA를 상태별로 `경기 정보 / 중계 보기 / 경기 기록 / 하이라이트`로 분리하고, 종료 경기에서 알림 중심 CTA가 보이지 않도록 개선
- web preview에서 `/#/schedule`, `/#/records`, `/#/game/...` 직접 진입 시 앱 부트스트랩 이후 `/home`으로 돌아가던 라우터 상태 보존 문제를 수정
- 일정 화면 최초 로딩에서 새로고침 indicator와 중앙 loading spinner가 동시에 보일 수 있던 중복 로딩 UI를 단일 spinner로 정리
- 하단 탭, 부트/온보딩, 경기 상세/진단 화면 전환에 공통 모션을 적용해 앱 화면 이동이 더 부드럽게 보이도록 개선
- iOS Widget / Live Activity / Dynamic Island에서 현재 타석 정보가 없을 때 B/S/O가 `0`으로 보이지 않도록 개선
- 홈 위젯을 누르면 현재 표시 중인 경기 상세로 바로 이동하고, 갱신이 늦은 위젯은 `업데이트 지연`으로 표시되도록 개선
- 현재 날짜/현재 시즌 데이터 요청에서 fresh cache도 먼저 반환하던 공통 캐시 분기를 수정해, 오늘 경기/일정/순위/기록실이 정상 상황에서는 API 최신 응답을 먼저 받도록 개선
- 온보딩 구단 선택 카드가 초소형 엠블럼 이미지를 확대하지 않도록 더 큰 공식 엠블럼 경로와 고품질 필터링을 적용
- 경기 상세에서 종료 경기 하이라이트가 탭 진입을 가리지 않도록 스코어 탭 하단으로 이동하고, `중계 보기` 진입 시 중계 탭이 우선 보이도록 정리
- 설정의 알림 전달 용어를 `바로 알림 / 묶음 요약 / 따라가기만 / 끄기`로 정리
- 기록실 overview snapshot이 오래된 shape여도 OPS+ 리더보드를 현재 API 계약에 맞춰 보정해 빈 카드가 나오지 않도록 개선
- 설정의 `알림 플레이북`과 경기 상세 `경기 따라가기`를 v4 Moment Subscription / Surface Strategy 시안에 맞춰 정리하고, Push / 따라가기 / 홈 위젯 역할을 더 명확하게 표시
- Android에서도 `경기 따라가기`를 진행형 알림으로 표시해 스코어, 이닝, 업데이트 시각을 앱 밖에서 따라볼 수 있도록 개선
- 홈, 경기 상세, 일정, 기록실, 설정 화면의 실제 Flutter UI를 v4 compact dark sports 톤으로 정리하고, 390px 모바일 폭 기준 카드/탭/헤더 밀도를 조정
- 설정 화면의 알림 설정을 `알림 플레이북`으로 바꿔 경기 시작, 득점, 홈런, 역전, 경기 종료, 라인업, 이닝 교대별로 `바로 / 요약 / Live만 / 끄기`를 선택할 수 있도록 개선
- 앱 시작 직후 알림 권한을 요청하지 않고, 사용자가 권한 확인, 바로 알림, 경기 따라가기 같은 명시적 동작을 선택한 뒤에만 OS 권한을 요청하도록 조정
- 경기 상세 라이브 경기 화면에 `경기 따라가기`를 추가하고, Live Activity는 앱이 자동으로 고른 경기가 아니라 사용자가 선택한 경기만 따라가도록 변경
- 위젯 / Live Activity 갱신이 별도 KBO direct crawling 루프를 만들지 않도록 compact scoreboard API를 사용하고, current-at-bat 직접 조회를 제거
- 최초 실행 원격 데이터 prefetch가 끝나지 않아 시작 화면에 머무를 수 있던 구조를 제거하고, 홈 화면 진입 뒤 백그라운드로 갱신하도록 조정
- KBO 라이브 상세 응답에서 총점 필드가 비어 있고 이닝별 점수만 있는 경우에도 합산 점수로 라이브 스코어를 표시하도록 보정
- 경기 상세가 오늘/미래 경기의 오래된 snapshot을 먼저 사용하지 않도록 조정해 경기 중 0:0 상세가 남는 문제를 수정
- 경기 종료 전환 직후 KBO scroll scoreboard가 비어도 보조 이닝표와 main score로 상세 스코어/이닝표를 표시하도록 보강
- 웹 경기 상세 캐시 키를 갱신해 기존 0:0 상세 캐시를 재사용하지 않도록 조정
- 기본 앱 데이터 경로에서 direct KBO crawling fallback과 과도한 startup/detail preload를 제거해, 홈/일정/경기 상세 진입 시 불필요한 웹 원본 호출이 발생하지 않도록 조정
- 백엔드가 같은 날짜 scoreboard 동시 요청을 한 번의 원천 조회로 합치고, 경기 단건 상세 조회가 같은 날짜 전체 경기 상세를 함께 불러오지 않도록 조정
- KBO 원천 웹 응답이 느리거나 깨질 때 일정/기록실이 더 버티도록 월간 일정 snapshot 저장 조건을 완화하고 records leaderboard snapshot 및 앱 bundled overview fallback을 추가
- 박스스코어와 문자중계의 현재 타석 주자 상태가 KBO 응답의 베이스 이미지 경로를 못 읽은 경우에도 주자 이름 기반으로 `주자1루`, `주자1,3루`, `만루` 등으로 표시되도록 보강
- 라인업 탭 선발투수 카드가 선수목록 조회 지연/이름 표기 차이에 막히지 않도록 KBO main game의 선발투수 id 기반 이미지 URL을 직접 사용하고, 백엔드 라인업 API도 starter id/imageUrl을 함께 내려주도록 보강
- local iPhone direct KBO 모드에서 문자중계가 startup/history warm 요청과 선수 프로필 대량 조회 뒤에 밀려 로딩 상태에 오래 머무를 수 있던 경로를 줄이고, 경기 상세 자동 새로고침이 진행 중 요청을 반복 invalidate 하지 않도록 조정
- 홈/일정/경기 상세 진입 경로에서 문자중계, 박스스코어, 라인업 데이터와 주요 선수 프로필 이미지를 미리 로딩해 상세 탭 첫 진입 대기감을 줄이도록 조정
- 일정 탭의 오늘 경기 상태를 `Main.asmx` live 메타데이터로 보정해 진행 중 경기가 `경기 전`으로 표시되는 문제를 수정
- 마이팀을 선택하지 않았을 때 마이팀 경기 푸시가 리그 전체 토픽으로 잘못 연결될 수 있던 동작을 수정
- FCM 토큰 갱신 시 현재 저장된 응원팀 기준으로 푸시 토픽을 다시 동기화하도록 보정
- 종료/취소/서스펜디드 경기에서는 일정 카드와 경기 상세의 예매 정보를 숨기도록 정리
- 경기 상세 문자중계 탭에서 현재 타석과 주요 플레이에 선수 프로필 이미지를 함께 보여주고, 볼/스트라이크/아웃 카운트를 색상 중심으로 더 빠르게 읽을 수 있도록 개선
- 경기 상세 문자중계에서 이닝 칩을 눌러 특정 회차 중계만 골라 볼 수 있도록 개선
- 경기 상세 문자중계를 타석별 카드 중심 레이아웃으로 다듬어, 선수 프로필과 투구 로그를 한 번에 읽기 쉽게 개선
- 경기 상세 박스스코어의 핵심 타자/핵심 투수 카드에 선수 프로필 이미지와 더 강한 텍스트 대비를 적용해 가독성을 개선
- 홈 `지금 보면 좋은 정보`의 선수 카드 탭 시 최근 기록 요약을 먼저 보고 선수 상세로 이어질 수 있도록 개선
- iOS 잠금화면 Live Activity에서 점수 영역이 양끝으로 벌어지지 않도록 중앙 배치로 조정
- iOS 잠금화면 Live Activity와 iOS 위젯 점수 영역에 팀 로고를 함께 표시하도록 개선
- iOS 잠금화면 Live Activity와 iOS 위젯에 현재 타석 타자/투수와 투구 수를 함께 표시하도록 개선
- `local` 환경에서도 홈 경기 이벤트 로컬 알림이 동작하도록 조정
- 경기 이벤트 알림 범위를 홈런, 이닝 교대, 선발 라인업 공개/변경까지 확장
- 설정 화면 알림 토글에 `라인업`, `이닝 교대`를 추가하고 로컬/원격 등록 payload를 함께 정리
- 배포/서명 문서에 GitHub Actions 기반 빌드본 추출 절차와 필요한 CI 시크릿 항목을 추가
- 웹에서 온보딩, 홈, 일정, 순위, 설정 화면이 브라우저 전체 폭으로 과도하게 늘어나지 않도록 모바일 폭 기준 레이아웃으로 정리
- 홈 화면의 마이팀 미선택 상태 CTA와 오늘의 야구 빠른 이동 동선을 보강
- 일정 화면에 달력 범례를 추가해 마이팀 경기일과 일반 경기일을 더 쉽게 구분하도록 개선
- 순위 화면 상단에 마이팀 현재 위치 요약 카드를 추가해 핵심 순위를 먼저 확인할 수 있도록 개선
- 설정 화면에 알림별 설명 문구를 추가해 어떤 알림이 오는지 더 쉽게 이해할 수 있도록 개선
- 앱 부트스트랩에 timeout/fallback 을 추가해 웹에서 저장소 응답 지연 시 스플래시 화면에 오래 머무를 가능성을 줄이도록 보강
- 웹 HTML 스플래시에 DOM 감지/timeout 제거 fallback 을 추가해 초기 렌더 지연 시 검은 대기 화면이 오래 남지 않도록 보강
- 정적 빌드 기반 웹 프리뷰 실행 경로(`./scripts/codex-run.sh web-static`, `./scripts/codex-run-web-static.sh`)를 추가
- 기본 웹 실행 래퍼(`./scripts/codex-run-web.sh`)를 정적 프리뷰 기준으로 전환하고, Chrome 디버그 실행을 `./scripts/codex-run-web-dev.sh`로 분리
- 백엔드 스코어보드 API가 `yyyyMMdd` 형식 날짜 요청도 처리하도록 보강해 웹 홈 화면에서 발생하던 날짜 포맷 오류를 줄임
- 웹 경기 상세 하이라이트에서 인라인 재생을 유지하면서 `스크롤 / 플레이어 조작` 모드 전환으로 스크롤 잠김을 줄이도록 조정
- 앱 시작 직후 홈, 일정, 순위, 기록실 데이터를 백그라운드로 미리 불러오도록 조정해 첫 탭 진입 대기시간을 줄임
- 앱이 FCM 토큰과 토픽 구독을 실제로 동기화할 수 있도록 원격 푸시 등록 경로를 연결
- 백엔드에 Firebase Admin 기반 테스트 푸시 발송 endpoint를 추가
- 홈 화면 상단에 `마이팀 브리프`, `오늘의 야구`, `빠른 콘텐츠` 영역을 추가해 경기 없는 날에도 야구 정보가 먼저 보이도록 개선
- 기록실 팀 화면이 선수 목록과 팀 스탯을 한 번에 받아오도록 바꿔 초기 로딩 지연을 완화
- 백엔드 기록실 크롤링 일부를 병렬화해 팀 기록 관련 최초 응답 속도를 개선
- 백엔드가 팀 기록실 응답을 짧게 캐시하도록 조정해 같은 팀 재진입 속도를 개선
- 기록실 팀 선택 화면이 웹에서 모든 구단 선수 데이터를 한꺼번에 불러오지 않도록 정리해 초기 진입 속도와 안정성을 개선
- 기록실 첫 화면에서 리그 리더보드/추천 선수 중심으로 먼저 보여주고, 팀 상세 진입 시에만 선수 데이터를 조회하도록 조정
- 기록실 첫 화면 리더보드에 리그 홈런 순위를 추가
- 크롤링 기반 기록 API가 느릴 때 웹에서 먼저 끊기지 않도록 앱 API 타임아웃을 완화해 기록실 상세 안정성을 개선
- 설정 화면의 `전체 경기 알림` 안내 문구가 실제 스위치 상태와 일치하도록 수정
- 일정 화면 경기 카드 상태 문구를 `경기 전 / 경기 중 / 경기 종료`로 정리하고, 점수가 있는 경기는 카드 중앙에 스코어를 함께 표시하도록 개선
- 저장소 소개, 실행 방법, 문서 우선순위를 루트 README에서 바로 확인할 수 있도록 정리
- README에 Codex 앱 실행 액션 등록용 공용 명령 추가
- `scripts/codex-run.sh`에 Chrome 기반 웹 실행 명령 추가
- Codex 액션 등록 권장 경로를 `ios/android/web` 분리 스크립트 기준으로 정리
- 에이전트/프로젝트 컨텍스트 문서에 README 및 CHANGELOG 지속 갱신 규칙 반영
- 백엔드 타입 힌트를 Python 3.9 호환 문법으로 정리해 `uvicorn` 실행 오류 수정
- Firebase iOS 플러그인 요구사항에 맞춰 iOS 최소 배포 버전을 `15.0`으로 상향
- 웹/릴리즈 기록실이 KBO 기반 백엔드 선수 API를 사용하도록 연결
- iOS Xcode 프로젝트의 플랫폼 설정을 시뮬레이터/기기 공용으로 정리
- 일정 화면에서 종료 경기 상세 진입 시 `경기를 찾을 수 없습니다`가 뜨던 문제를 수정해 `gameId` 기반 상세 재조회가 가능하도록 보완
- 백엔드에 `/game/{gameId}` 단건 조회를 추가해 웹/릴리즈 환경에서도 경기 상세 진입이 동작하도록 수정
- 일정/상세 API 응답에 예매처와 예매 오픈 시간 정보를 포함하도록 확장
- 디바이스 로컬 예약 알림으로 예매 오픈 시각 알림을 받을 수 있게 보완하고, 리마인드를 하루 전 / 1시간 전 / 10분 전으로 확장
- 경기 상세 API에서 KBO 공식 하이라이트 링크와 유튜브 검색 기반 메타데이터를 함께 내려주도록 확장
- 문자중계 API 미구현 상태에서 상세 탭에 raw 오류가 노출되지 않도록 경기 상태별 안내 문구로 정리
- 문자중계 탭의 중복 API 호출을 제거하고, relay API가 빈 응답을 반환하도록 정리해 웹 콘솔 오류를 줄임
- KBO 일정의 `START_PIT` 프리뷰 링크를 예정 경기로 인식하도록 보정해 예정 경기 상세 상태가 `UNKNOWN`으로 내려오지 않게 수정
- 종료 경기 문자중계 탭에 이닝별 득점 흐름과 최종 결과를 보여주는 summary relay를 추가
- KBO 로그인 세션이 설정된 경우 `LiveTextView2.aspx` 기반의 실제 play-by-play relay를 파싱해 문자중계 탭에 제공하도록 확장
- relay 서비스가 종료 경기에서는 요약형 득점 흐름을 우선 사용하고, live 경기에서는 현재 타석 정보를 더 안정적으로 보강하도록 정리
- 경기 상세 화면의 누락된 라인업 탭 파일과 생성자 불일치를 수정해 웹 빌드 실패를 해결
- 예정 경기 scoreboard 응답에 세부 테이블이 없어도 홈 화면이 500 없이 열리도록 보강하고, 예정 경기 문구를 올바르게 표시하도록 수정
- 홈/순위 화면 에러 메시지를 사용자용 문구로 정리하고, 개발 환경에서는 API 응답 시간을 Dev Console 에 기록하도록 보강
- 기록실 캐시를 공통 TTL 캐시 유틸로 정리하고, 예정 경기에서는 YouTube 하이라이트 검색을 생략해 첫 로딩 불필요 호출을 줄임
- 날짜별 스코어보드 응답도 짧게 캐시하고 경기별 enrich 를 병렬화해 홈 재진입 속도를 추가로 개선
- 홈/기록실 실측 지표를 서버 로그로도 수집하고, 웹에서 `API 진단` 화면으로 `health / scoreboard / schedule` 상태를 함께 확인할 수 있도록 추가
- KBO 원본 호출에 circuit breaker 와 stale cache fallback 을 도입해 외부 응답 불안정 시 홈/기록실 복원력을 높임
- 라인업 탭을 모바일 가독성 중심 카드형 레이아웃으로 개편하고, `AWAY/HOME`와 함께 실제 팀명과 로고를 표시하도록 개선
- 홈 진입 속도 개선을 위해 스코어보드 API에서 상세용 유튜브 하이라이트 검색을 분리
- iOS/Android 런치 스크린을 다크 테마로 정리해 앱 시작 시 흰 화면이 길게 보이는 현상을 완화
- Android release signing 이 `key.properties` 기반 구조를 사용하도록 정리
- 지난 경기 결과, 선수 과거 기록, 지난 날짜 순위를 저장된 snapshot 우선으로 읽는 데이터 전략을 문서 기준으로 확정해 히스토리 화면 로딩 없이 즉시 보여줄 수 있는 방향을 정리

## [0.0.7] - 2026-05-19

### Changed

- 설정의 알림 전달 방식을 `바로 알림`, `묶음 요약`, `따라가기만`, `끄기`로 정리
- 경기 상세에서 라이브 경기 `경기 따라가기`를 사용자가 직접 시작하도록 변경
- iOS 위젯과 Live Activity에서 점수, 팀 로고, 현재 타석 정보를 더 안정적으로 표시하도록 개선
- 초기 rolling snapshot의 마지막 기준으로 정리

## [0.0.6] - 2026-05-19

### Changed

- compact scoreboard, 위젯/Live Activity 데이터, release API health gate 방향 정리
- 홈과 경기 상세의 앱 밖 표면을 API-first 기준으로 축소
- release 빌드 전 production API DNS/TLS/핵심 endpoint를 확인하는 guard 도입

## [0.0.5] - 2026-04-11

### Changed

- Firebase, Android/iOS 배포 준비, signing 문서, tester 공유 흐름 정리
- 알림과 경기 따라가기 표면을 외부 테스트 준비 기준으로 확장

## [0.0.4] - 2026-04-11

### Changed

- 기록실, 선수 상세, 팀 기록, 경기 상세의 기본 구조를 앱 주요 화면으로 확장
- 일정, 순위, 예매 정보, 하이라이트 연결을 MVP 화면 흐름에 포함

## [0.0.3] - 2026-03-31

### Changed

- 마이팀 중심 UX, Dynamic Island/Live Activity 방향, 일정/상세 polish를 초기 검증
- 현재 진행 중이거나 오늘 예정된 마이팀 경기를 앱 밖 표면의 우선 후보로 다루는 방향 정리

## [0.0.2] - 2026-03-31

### Changed

- 초기 실행 스크립트, 문서, 위젯/Live Activity 후속 방향 보강
- 반복 작업을 `.claude/skills/`로 분리하고 AGENTS/CLAUDE 문서 기준을 동기화

## [0.0.1] - 2026-03-31

### Added

- Flutter 앱 골격, FastAPI backend 골격, MVP 화면 구조, 프로젝트 문서의 첫 릴리즈

## [2026-03-30]

### Added

- `AGENTS.md` 작성 및 저장소 작업 규칙 정리
- `backend/` FastAPI 기본 구조, 라우터 스텁, health endpoint, 테스트 추가
- `docs/TASK_DIVISION.md` 협업 운영 문서 정리

### Changed

- 모바일 기준 스택을 Flutter + Dart로 재확인
- `CLAUDE.md`와 `AGENTS.md`를 `docs/FIGMA_PROMPT.md` 및 최근 결정 기준으로 보강

## [2026-03-28]

### Added

- 프로젝트 초기 문서 세트 작성
  - `CLAUDE.md`
  - `docs/PLANNING.md`
  - `docs/APP_SPEC.md`
  - `docs/WORKLOG.md`
- Git 저장소 초기 설정

### Changed

- 모바일 프레임워크 방향을 React Native(Expo)에서 Flutter로 변경
- 인프라 방향을 AWS 기반으로 확정
