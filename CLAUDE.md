# KBO Fans 프로젝트

## 프로젝트 개요
KBO 프로야구 팬을 위한 실시간 경기 정보 모바일 앱 (iOS/Android)

### 제품 목표
- 앱을 열면 바로 오늘 경기 상황을 확인할 수 있는 야구 특화 경험 제공
- 코어팬에게는 문자중계/박스스코어/라인업을, 라이트팬에게는 마이팀 중심 빠른 확인 경험 제공
- 네이버 스포츠나 SPORTS.i보다 가볍고 집중된 UX를 지향

## 기술 스택
- **모바일**: Flutter + Dart
- **백엔드**: Python FastAPI active runtime component (API-backed data, snapshot generation, push, Live Activity / Dynamic Island sync)
- **크롤링**: requests + BeautifulSoup (KBO 홈페이지)
- **상태관리**: Riverpod
- **네비게이션**: go_router
- **HTTP**: dio
- **인프라**: AWS (EC2/ECS + RDS PostgreSQL + ElastiCache Redis)
- **푸시**: Firebase Cloud Messaging + APNs ActivityKit Live Activity push

## 프로젝트 구조

```text
kbo_fans/
├── CLAUDE.md              # 이 파일
├── AGENTS.md              # Codex 작업 가이드
├── README.md              # 저장소 소개 / 실행 방법 / 빠른 시작
├── CHANGELOG.md           # 사용자 관점 변경 이력
├── docs/
│   ├── PLANNING.md        # 서비스 기획서
│   ├── APP_SPEC.md        # 앱 상세 기획서 (화면별 + API 명세)
│   ├── FIGMA_PROMPT.md    # Figma 와이어프레임/디자인 생성 기준
│   └── WORKLOG.md         # 작업 이력
├── design_docs.docx       # 수업 제출용 기획서
├── backend/               # Python FastAPI API service, snapshot tooling, push / Live Activity backend
└── app/                   # Flutter 앱 구현체
```

## 문서 우선순위
- 저장소 전반 작업 기준: `AGENTS.md`
- 프로젝트 개요와 큰 방향: `CLAUDE.md`
- 재사용 가능한 작업 패턴/스킬: `.claude/SKILL_REFERENCE.md`
- 저장소 소개/실행 가이드: `README.md`
- 외부 공개용 변경 이력: `CHANGELOG.md`
- 버전/태그/릴리즈/앱 내 업데이트 소식 정책: `docs/VERSIONING.md`
- 배포 / 테스터 공유 가이드: `docs/DISTRIBUTION_GUIDE.md`, `docs/ANDROID_SIGNING_GUIDE.md`, `docs/IOS_TESTFLIGHT_CHECKLIST.md`
- 제품 목표/UX 원칙/로드맵: `docs/PLANNING.md`
- 화면 상세, 상태, API 계약: `docs/APP_SPEC.md`
- 구현 인사이트/배포 메모: `docs/ENGINEERING_NOTES.md`
- Figma 화면 구성, 다크 테마, 컬러/레이아웃 기준: `docs/FIGMA_PROMPT.md`
- 최신 작업 이력과 결정 사항: `docs/WORKLOG.md`
- 문서가 충돌하면 최신 결정은 `docs/WORKLOG.md`와 실제 코드/산출물을 우선한다

## Git 설정
- **레포**: github.com/godekd3133/kbo-fans (Private)
- **SSH**: `github-personal` alias → `~/.ssh/andy` 키 → godekd3133 계정
- **remote**: `git@github-personal:godekd3133/kbo-fans.git`

## 작업 규칙
- 모든 작업 상황은 MD 파일로 기록한다
- 피처/작업 단위의 컨텍스트를 `docs/` 아래에 MD로 남긴다
- 작업 이력은 `docs/WORKLOG.md`에 누적한다
- 실행 방법, 프로젝트 구조, 현재 구현 범위가 바뀌면 `README.md`를 함께 갱신한다
- 사용자 관점의 기능/마일스톤 변경이 생기면 `CHANGELOG.md`를 함께 갱신한다
- 버전이나 릴리즈가 바뀌면 `CHANGELOG.md`, 앱 내 업데이트 소식(`app/assets/bootstrap/patch_notes.md`), GitHub 릴리즈 노트를 같은 단위로 갱신한다
- 앱 내 업데이트 소식은 사용자에게 보이는 화면/알림/데이터 변화 중심으로 쓰고, 배포 checkpoint나 서버/워크플로 세부는 `CHANGELOG.md`, GitHub Release, `docs/WORKLOG.md`에 분리한다
- 앱 내 업데이트 소식은 `새로워졌어요`, `고쳤어요`, `빨라졌어요`, `작게 다듬었어요`처럼 유저가 훑기 쉬운 분류를 우선하고, 사소한 변경·구체적인 버그 수정·성능/안정성 개선도 뭉뚱그리지 않고 적는다
- Codex 앱 실행 액션으로 쓰는 공용 명령은 가능하면 `scripts/` 아래 스크립트로 유지한다
- Codex 앱 실행 액션을 플랫폼별로 분리할 때는 `ios`, `android`, `web` 각각 독립 스크립트 진입점을 둔다
- Codex 앱 액션은 저장소 스크립트를 만든다고 UI에 자동 등록되지 않으므로, 사용자 수동 등록이 필요하다는 전제를 유지한다
- 반복되는 작업은 `.claude/skills/` 로 뺄 수 있으면 빼고, 관련 진입점을 문서에 같이 남긴다
- 백엔드 최소 런타임은 `backend/pyproject.toml` 기준 Python `3.9`로 본다
- 백엔드 코드에서는 Python 3.10+ 전용 타입 문법(`int | None`, `str | None`)을 쓰지 않고 `Optional[...]`, `Union[...]`을 사용한다
- 커밋은 한글로 작성한다
- Flutter, FastAPI, Figma 산출물은 문서와 함께 같이 업데이트한다
- 화면/UX 변경 시 `docs/APP_SPEC.md`와 `docs/FIGMA_PROMPT.md` 반영 여부를 같이 확인한다

## 런타임 / 운영 메모
- 백엔드는 active runtime component다. 데이터 라우팅, push, Live Activity, snapshot, release routing, API 계약을 건드리면 `app/`과 `backend/`를 함께 본다
- Flutter provider routing은 모든 빌드에서 backend API가 기본이다. 스크립트/CI에는 예측 가능성을 위해 `USE_BACKEND_API=true` 를 명시하고, `USE_BACKEND_API=false` 는 direct KBO parser/debug 세션에서만 사용한다
- direct KBO mode는 명시적 parser parity/debug 경로로만 유지한다. 일반 local/dev/release/web/native 빌드나 tester-facing artifact의 기본값으로 쓰지 않는다
- 앱 종료 후 일반 푸시와 iOS Live Activity / Dynamic Island를 계속 갱신하는 기능은 운영 백엔드가 KBO 상태를 polling하고 FCM/APNs로 발송해야 한다
- release build는 화면 데이터와 push / Live Activity token registration 모두 운영 backend API 기준으로 검증한다. 운영 `API_BASE_URL`과 backend health/readiness를 함께 확인한다
- AWS ECS/Fargate 시연 배포는 `infra/aws/ecs-fargate/`의 API service + sync worker service 템플릿을 기준으로 한다. Secrets Manager 값은 `FIREBASE_SERVICE_ACCOUNT_JSON`, `APNS_AUTH_KEY_P8`, `PUSH_SYNC_SECRET` env로 주입한다
- 시연 배포 전에는 `./scripts/push-live-preflight.sh --env-file /path/to/kbo-fans-aws.env --aws`로 앱 Firebase 파일, APNs/Live Activity capability, release `API_BASE_URL` token-registration handoff, backend secret env, AWS env 형태를 secret 출력 없이 점검한다
- `infra/aws/ecs-fargate/deploy.env.example`를 push preflight, 로컬 AWS 배포, GitHub Actions secrets/variables 업로드의 단일 checklist로 사용한다. untracked env 파일로 복사한 뒤 파일 안 주석을 따라 placeholder를 모두 실제 값으로 바꾸고 `--apply`를 실행한다
- push demo 준비 흐름이 헷갈리면 `./scripts/push-demo-setup-status.sh --env-file /tmp/kbo-fans-aws.env --repo godekd3133/kbo-fans`를 먼저 실행한다. env 초안 생성, OIDC dry-run, readiness audit, 다음 명령 안내를 묶고 배포나 workflow dispatch는 하지 않는다
- `./scripts/push-demo-readiness-audit.sh --env-file /path/to/kbo-fans-aws.env --repo godekd3133/kbo-fans`로 앱 파일, env checklist, 로컬 tooling, GitHub Actions 입력값, 최신 deploy run을 배포 없이 점검한다. secret 값은 출력하지 않는다
- AWS push secret은 `./scripts/aws-push-secrets.sh`로 생성/갱신하고, 출력되는 `SECRET_ARN_*` 값을 task definition 렌더링에 사용한다
- backend ECR image는 `./scripts/aws-push-image.sh`로 build/tag/push하고, 특정 tag 배포 시 `outputs/aws/ecr/image.env`의 `CONTAINER_IMAGE_URI`를 사용한다
- ECS task definition과 execution-role secret-read policy는 placeholder JSON을 직접 편집하지 않고 `./scripts/aws-push-task-definitions.sh` 또는 `./scripts/codex-run.sh aws-push-task-defs`로 렌더링한다
- ECS task 등록이나 service 생성 전 `./scripts/aws-push-deploy-check.sh`로 env, rendered JSON, secret, IAM role, ECR, EFS, CloudWatch log group 존재 여부를 점검한다
- ALB, ECS service 2개, EFS registry, IAM role, log group을 한 번에 만들 때는 `./scripts/aws-push-cloudformation.sh`를 사용한다
- 도메인/ACM certificate가 아직 없으면 임시 AWS backend smoke에만 `ENABLE_HTTPS=false`를 쓴다. iPhone release token registration은 `ENABLE_HTTPS=true`와 `API_DOMAIN_NAME`, `ACM_CERTIFICATE_ARN` 기준으로 되돌린다
- CloudFormation stack output은 `./scripts/aws-push-stack-outputs.sh`로 추출하고, `outputs/aws/cloudformation/stack.env`의 `RELEASE_API_BASE_URL` / `API_BASE_URL`을 release build에 주입한다
- 전체 시연 배포는 `./scripts/aws-push-demo-deploy.sh`를 우선 사용한다. secret 업로드, image push, CloudFormation deploy, output export, readiness를 순서대로 실행한다
- 로컬 AWS CLI 또는 Docker daemon이 준비되지 않았으면 GitHub Actions `Push Demo Deploy` workflow를 사용한다. 필요한 AWS/Firebase/APNs secrets/vars는 `docs/PUSH_LIVE_ACTIVITY_BACKEND_SETUP.md`에 맞춘다
- GitHub Actions push deploy secrets/vars를 준비할 때는 `./scripts/github-push-secrets.sh --env-file /path/to/kbo-fans-aws.env` dry-run을 먼저 보고, 실제 업로드는 `--apply`를 붙인다. secret 값은 출력하지 않는다
- workflow 파일을 커밋/푸시한 뒤 `./scripts/github-push-demo-run.sh --dry-run true --watch`로 dry-run을 실행하고, 통과 후 `--dry-run false --watch`로 실제 배포한다. 이 스크립트는 dispatch 전에 필수 GitHub secrets/variables를 확인하며, 별도 점검을 끝낸 경우에만 `--skip-config-check`로 우회한다
- Live Activity scoreboard sync 기본 날짜는 KBO 경기일 기준인 `Asia/Seoul`로 계산한다. AWS UTC `date.today()` 기준으로 바꾸지 않는다
- 홈 첫 진입은 설정된 현재 scoreboard source를 우선하고, 이후 background refresh 방식으로 체감 속도를 확보한다
- 지난 경기 결과, 과거 시즌 순위, 기록실 과거 시즌 데이터는 snapshot 우선 전략을 유지한다
- 앱 번들 standings / records overview fallback 은 exact-season-only 로 제한한다. 현재 시즌은 `generatedAt` 기준 최신 snapshot 만 허용하고, 검증되지 않은 과거 시즌은 다른 시즌 데이터를 빌리지 않는다
- 명시적 API-backed current 경로에서 현재 시즌 팀 선수 / 팀 스탯 / 선수 상세 실패는 backend/app/device snapshot 으로 숨기지 않는다
- records overview / leaderboard API cache 와 기기 snapshot 은 리더보드가 1위부터 시작할 때만 저장/재사용한다. malformed cache shape 을 무효화할 때는 cache key 또는 device snapshot version 을 올린다
- backend 현재 스코어보드, 일정, 순위, 기록실 요약, 리더보드는 crawler 실패 시 snapshot fallback 을 쓰지 않는다. 과거 날짜/시즌/월은 저장 snapshot 우선 전략을 유지한다
- backend records overview / leaderboard 응답은 cache/save/return 전에 rank 오름차순으로 정규화한다
- backend `/home` aggregate 는 현재/미래 날짜에서 schedule / standings / records overview 실패를 빈 섹션이나 placeholder 로 숨기지 않는다. 과거 날짜 홈 조회만 partial fallback 을 허용한다
- 앱 cache 는 현재 날짜/월/시즌 데이터의 실패 fallback 으로 쓰지 않는다. `allowCacheOnFailure` 기본값은 false 로 유지하고, historical 경로만 cached-first/snapshot 정책을 명시적으로 허용한다
- 박스스코어 adjacent game id fallback 은 과거 경기 canonical id 보정에만 허용한다. current/live 박스스코어는 전날 같은 팀 경기 선수 기록을 빌리지 않고 official-unavailable 상태로 노출한다
- 홈 첫 로딩은 오늘 스코어보드 별도 local cache 를 먼저 렌더링하지 않는다. 최신 direct source 데이터 또는 명시적 loading/error 상태만 보여준다
- 홈 secondary aggregate provider 는 첫 scoreboard 데이터 프레임 이후에만 구독한다
- 홈 refresh timer 는 unrelated rebuild 때 cancel/restart 하지 않고 interval 또는 scoreboard signature 변경 시에만 재스케줄한다
- backend `/scoreboard/home`과 `/scoreboard/compact`는 홈/위젯 요약 전용 경로라 경기별 상세 스코어보드 크롤러를 호출하지 않는다. 상세 크롤링은 full scoreboard 와 game detail 로 제한한다
- backend current data route 는 `api/runtime_services.py` singleton 을 공유해 sibling endpoint 간 TTL cache 를 재사용한다
- LIVE 요약 스코어보드는 KBO main list 의 유효한 득점을 schedule/detail fallback 의 0점보다 우선해, 진행 중 경기의 최신 score가 fallback 0:0에 막히지 않게 한다
- 앱 UI는 scoreboard 팀 합계 H/E/B가 `null`인 값을 실제 0 기록처럼 렌더링하지 않는다
- 앱 전역 Provider retry 는 비활성화한다. API 실패를 자동 재시도로 숨기지 말고 화면 오류 상태와 Dev Console 로그로 드러낸다
- 팀 기록실은 팀 리스트 → 팀 상세 진입 구조를 기본 정보 구조로 본다
- Git push 시 기본 `origin` 이슈가 있으면 `git@github-personal:godekd3133/kbo-fans.git` 경로를 사용한다

## 저장소 스킬
- `.claude/skills/kbo-runtime-data/SKILL.md`
  - 데이터 로딩 경로, API/direct 선택, cache/snapshot, 성능 검증용 가이드
- `.claude/skills/kbo-release-flow/SKILL.md`
  - 커밋/푸시/숫자 릴리즈 태그/TestFlight 전환 시 체크해야 할 저장소 전용 릴리즈 가이드
- `.claude/skills/kbo-version-release/SKILL.md`
  - 앱 버전 변경, GitHub 릴리즈/태그 정리, 앱 내 업데이트 소식 갱신 루틴
- `.claude/skills/app-startup-runtime-triage/SKILL.md`
  - 앱 시작 흰 화면, local API base URL, Dev Console 로그 노이즈, Firebase local 경고 트리아지용 가이드
- `.claude/skills/ios-device-run-action/SKILL.md`
  - 연결된 iOS 실기기 우선 실행 액션, `flutter devices`/`xcodebuild` destination 불일치 점검 가이드

## 최근 구현 인사이트
- 실기기 디버그 환경에서 `localhost` 백엔드는 직접 닿지 않는다. `USE_BACKEND_API=true` 와 LAN 접근 가능한 `API_BASE_URL` 을 함께 주입한다.
- 데이터 소스 혼선은 실제 장애처럼 보이므로 화면별로 다른 저장소를 보게 두지 않는다.
- 현재 backend 방향:
  - FastAPI는 API-backed data, snapshot generation, push, Live Activity / Dynamic Island sync의 active component다.
  - direct KBO는 명시적 parser parity/debug 경로다.
- 기록실 선수 상세/엔트리 전체는 direct source 또는 생성된 snapshot 기준으로 유지한다.
- 순위/기록실 요약/리더보드는 요청 시즌과 정확히 맞는 검증된 snapshot 만 사용한다. 검증되지 않은 과거 순위는 빈 exact snapshot 으로 둔다.
- 명시적 API-backed 앱 모드에서는 current-season standings / records overview / leaderboard / team players / team stats / player detail API 실패를 앱 번들 bootstrap, 구형/fresh API cache, backend current snapshot 으로 숨기지 않는다.
- Dev Console 은 현재 API base URL, API latency, 홈/일정/기록실 로딩 완료 로그, 기록실 진단 로그를 표시하는 운영 도구다.
- direct 파서는 KBO 마크업 변경에 취약하므로, 수정 시 기존 parser/test 결과와 반드시 대조한다.
- `.claude/skills/`에 이미 같은 작업 패턴이 있으면 먼저 그 스킬을 참고한다
- 앱 UI 카피에는 이모지를 사용하지 않는다
- 히스토리 데이터는 원천 재크롤링보다 backend snapshot 우선이 현재 방향이다.
- 앱 히스토리 화면은 cached-first + background refresh, live 화면은 network-first 가 기본 원칙이다.

## 누적 인사이트
- 홈 첫 진입은 “스코어보드 우선, 나머지 섹션 후순위”가 체감 속도에 가장 중요하다
- 홈에서는 상세용 하이라이트/유튜브 검색을 절대 같이 물지 않는다
- 상세 하이라이트는 lazy endpoint 로 분리해야 실제 화면이 먼저 뜬다
- 앱 시작 전에 plugin init 을 기다리면 iOS/web 에서 흰 화면 원인이 되기 쉽다
- local Android API 연결은 `localhost` 대신 `10.0.2.2` 를 기본으로 보는 편이 안전하다
- Dev Console 은 성공/실패를 `API OK / API FAIL` 로 분리해야 원인 파악이 빠르다
- KBO relay는 비로그인으로 안정적으로 확보되지 않으며, 로그인 세션과 재시도 정책이 필요하다
- `LiveTextView2.aspx`가 현재 타석과 play-by-play의 핵심 source다
- 앱 direct KBO 경로에서는 `GetScheduleList` request shape 와 plain text decode 가 중요하다
- iOS 위젯/기기 이슈는 duplicate plugin, widget plist version, destination/platform support 순서로 본다
- 라인업/박스스코어는 표보다 모바일 카드형 레이아웃이 가독성이 훨씬 좋다

## 재사용 스킬
- KBO direct ASMX 연동: `.claude/skills/kbo-asmx-direct-integration/SKILL.md`
- iOS WidgetKit / Live Activity / 기기 실행 트리아지: `.claude/skills/ios-live-activity-widget/SKILL.md`
- 친구에게 가장 빨리 보여주는 경로는 웹이다
- iPhone 친구 배포는 TestFlight를 기본 경로로 본다
- 새 iOS TestFlight 빌드를 tester-facing release로 올릴 때는 외부 TestFlight 그룹도 즉시 최신 빌드로 갱신한다. 빌드가 `VALID`가 될 때까지 확인하고, `External Testers`에 최신 build를 연결한 뒤 Beta App Review가 없으면 바로 제출한다. 단, 최신 build가 승인되거나 외부 설치 가능 상태로 확인되기 전에는 마지막 승인/설치 가능 build를 제거하지 않는다. 보고할 때는 upload 성공, Apple processing/VALID, 외부 그룹 연결, Beta App Review, 실제 installability를 분리해서 말한다.
- Android 친구 배포는 release signing 설정 후 Google Play internal testing 을 기본 경로로 본다
- Android release signing 비밀값은 `app/android/key.properties` 와 local keystore 로 관리하고 Git에는 올리지 않는다
- iOS 실행/배포는 활성 Xcode 버전과 simulator/platform support 정합성에 크게 영향받는다
- Xcode Components 에 설치된 것으로 보여도 `xcodebuild -showdestinations` 에서는 platform 미설치로 막을 수 있다

## 데이터 소스
- KBO 공식 홈페이지 (koreabaseball.com) 크롤링
- 경로 1: ASP.NET SSR 페이지 → GET + BeautifulSoup
- 경로 2: ASMX 내부 API → POST → JSON
- 일부 relay/보호 페이지는 KBO 로그인 세션이 필요할 수 있으며, 자격증명은 로컬 secure storage(`.env`, Keychain)로만 관리한다. 저장소 문서나 코드에 평문으로 남기지 않는다.
- 상세 내용은 `docs/PLANNING.md` 참조

## UX / 디자인 방향
- 모바일 기준 프레임은 390x844(iPhone 14 기준)로 본다
- 전체 방향은 모던, 미니멀, 다크 모드 기반 스포츠 앱이다
- 핵심 컬러는 다크 배경(`#0F0F0F`, `#1A1A1A`)와 라이브 강조색(`#FF4444`)다
- 팀 컬러는 개인화, 마이팀 강조, 알림/선택 상태 표현에 적극 사용한다
- 주요 폰트 방향은 Jua(한글/영문/숫자)다. 장난감 같은 둥근 획으로 더 아기자기한 앱 톤을 만들고, NanumSquareRound와 Pretendard는 fallback으로 유지한다
- 공통 하단 탭은 `일정 / 순위 / 홈 / 기록실 / 설정` 5개 탭이며, `홈`을 가운데에 둔다

## 정보 구조
- 온보딩: 마이팀 선택
- 홈: 오늘의 스코어보드
- 경기 상세: 스코어 / 문자중계 / 박스스코어 / 라인업
- 일정
- 순위
- 설정
- 위젯: 홈화면/잠금화면 변형은 Phase 1.5 범위

## 디자인 작업 상태
- `docs/FIGMA_PROMPT.md` 기준으로 페이지별 와이어프레임/시안 생성 준비가 되어 있다
- Figma 작업 시 `User Flow`, 온보딩, 홈, 경기 상세 4탭, 일정, 순위, 설정, 위젯까지 포함한 구조를 기준으로 한다
- Figma MCP 접근 상태는 계정/권한 영향이 있으므로 실제 작업 전 연결 상태를 확인해야 한다

## 반복 작업 스킬
- 전체 스킬 인덱스: `.claude/SKILL_REFERENCE.md`
- 버전 변경 / GitHub 릴리즈 / 앱 내 업데이트 소식 갱신 시: `.claude/skills/kbo-version-release/SKILL.md`
- Director가 `이어서 해`라고 하면 diff 규모를 보고 새 숫자 버전 생성 또는 현재 GitHub Release notes 보강을 자율 판단한다.
- 히스토리 데이터 / snapshot-first 캐시 구조 작업 시: `.claude/skills/kbo-history-snapshot/SKILL.md`
- 아키텍처/API/UX 변경 후 문서 동기화 시: `.claude/skills/kbo-doc-sync/SKILL.md`
- iOS 위젯 / Live Activity / Dynamic Island 수정 시: `.claude/skills/ios-live-activity-widget/SKILL.md`
- TestFlight/Android 배포 준비 시: `.claude/skills/mobile-preview-release/SKILL.md`는 legacy 체크리스트로만 참고하고, 릴리즈 태그/버전은 `.claude/skills/kbo-version-release/SKILL.md`의 plain `0.0.x` 정책을 따른다
- 친구/테스터 배포 준비 시: `.claude/skills/app-distribution/SKILL.md`

## MVP 기능 (Phase 1)
1. 실시간 스코어보드
2. 문자중계
3. 박스스코어
4. 푸시 알림
5. 마이팀 설정
6. 경기 일정 / 팀 순위

## 다음 기본 우선순위
1. APNs Auth Key / Key ID / Team ID 준비 후 push demo backend secret 반영
2. iPhone 실기기에서 push, WidgetKit, Live Activity / Dynamic Island 동작 검증
3. TestFlight와 Android internal testing 배포 경로 확정
4. 발표 자료, Figma 기준, 기획 문서를 실제 앱 화면 캡쳐 기준으로 계속 동기화
5. release 전 direct KBO parser와 snapshot fallback 경계 회귀 검증

## Claude Skills
- `.claude/skills/bootstrap-fallback-data/SKILL.md`
  - 시즌별 standings / records overview 스냅샷 생성과 앱 fallback 연결 작업용
- `.claude/skills/app-icon-pipeline/SKILL.md`
  - 앱 아이콘 변형 제작, 선택, iOS/Android 리소스 갱신 작업용
