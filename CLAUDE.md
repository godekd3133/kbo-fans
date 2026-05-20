# KBO Fans 프로젝트

## 프로젝트 개요
KBO 프로야구 팬을 위한 실시간 경기 정보 모바일 앱 (iOS/Android)

### 제품 목표
- 앱을 열면 바로 오늘 경기 상황을 확인할 수 있는 야구 특화 경험 제공
- 코어팬에게는 문자중계/박스스코어/라인업을, 라이트팬에게는 마이팀 중심 빠른 확인 경험 제공
- 네이버 스포츠나 SPORTS.i보다 가볍고 집중된 UX를 지향

## 기술 스택
- **모바일**: Flutter + Dart
- **백엔드**: Python FastAPI (AWS 배포)
- **크롤링**: requests + BeautifulSoup (KBO 홈페이지)
- **상태관리**: Riverpod
- **네비게이션**: go_router
- **HTTP**: dio
- **인프라**: AWS (EC2/ECS + RDS PostgreSQL + ElastiCache Redis)
- **푸시**: Firebase Cloud Messaging

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
├── backend/               # Python FastAPI 서버 (예정)
└── app/                   # Flutter 앱 (예정)
```

## 문서 우선순위
- 저장소 전반 작업 기준: `AGENTS.md`
- 프로젝트 개요와 큰 방향: `CLAUDE.md`
- 재사용 가능한 작업 패턴/스킬: `.claude/SKILL_REFERENCE.md`
- 저장소 소개/실행 가이드: `README.md`
- 외부 공개용 변경 이력: `CHANGELOG.md`
- 버전/태그/릴리즈/패치노트 정책: `docs/VERSIONING.md`
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
- 버전이나 릴리즈가 바뀌면 `CHANGELOG.md`, 앱 내 패치노트(`app/assets/bootstrap/patch_notes.md`), GitHub 릴리즈 노트를 같은 단위로 갱신한다
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
- 웹과 release 빌드는 KBO 원본 직접 호출 대신 백엔드 API 경로를 기본으로 사용한다
- 로컬 네이티브 실행도 기본은 API 경로다. direct KBO crawler 경로는 `APP_ENV=local`, native runtime, `API_BASE_URL` override 없음, `PREFER_DIRECT_SCRAPE=true` 조건을 모두 만족하는 임시 direct-primary 빌드에서만 쓴다
- 홈 첫 진입은 경량 payload / 캐시 우선, 이후 background refresh 방식으로 체감 속도를 확보한다
- 지난 경기 결과, 과거 시즌 순위, 기록실 과거 시즌 데이터는 snapshot 우선 전략을 유지한다
- 앱 번들 standings / records overview fallback 은 exact-season-only 로 제한한다. 현재 시즌은 `generatedAt` 기준 최신 snapshot 만 허용하고, 검증되지 않은 과거 시즌은 다른 시즌 데이터를 빌리지 않는다
- 일반 API-backed current 경로에서 현재 시즌 팀 선수 / 팀 스탯 / 선수 상세 실패는 backend/app/device snapshot 으로 숨기지 않는다
- records overview / leaderboard API cache 와 기기 snapshot 은 리더보드가 1위부터 시작할 때만 저장/재사용한다. malformed cache shape 을 무효화할 때는 cache key 또는 device snapshot version 을 올린다
- backend 현재 스코어보드, 일정, 순위, 기록실 요약, 리더보드는 crawler 실패 시 snapshot fallback 을 쓰지 않는다. 과거 날짜/시즌/월은 저장 snapshot 우선 전략을 유지한다
- backend `/home` aggregate 는 현재/미래 날짜에서 schedule / standings / records overview 실패를 빈 섹션이나 placeholder 로 숨기지 않는다. 과거 날짜 홈 조회만 partial fallback 을 허용한다
- 앱 API cache 는 현재 날짜/월/시즌 데이터의 실패 fallback 으로 쓰지 않는다. `allowCacheOnFailure` 기본값은 false 로 유지하고, historical 경로만 cached-first/snapshot 정책을 명시적으로 허용한다
- 홈 첫 로딩은 오늘 스코어보드 별도 local cache 를 먼저 렌더링하지 않는다. 최신 API 데이터 또는 명시적 loading/error 상태만 보여준다
- 앱 전역 Provider retry 는 비활성화한다. API 실패를 자동 재시도로 숨기지 말고 화면 오류 상태와 Dev Console 로그로 드러낸다
- 팀 기록실은 팀 리스트 → 팀 상세 진입 구조를 기본 정보 구조로 본다
- Git push 시 기본 `origin` 이슈가 있으면 `git@github-personal:godekd3133/kbo-fans.git` 경로를 사용한다

## 저장소 스킬
- `.claude/skills/kbo-runtime-data/SKILL.md`
  - 데이터 로딩 경로, API/direct 선택, cache/snapshot, 성능 검증용 가이드
- `.claude/skills/kbo-release-flow/SKILL.md`
  - 커밋/푸시/숫자 릴리즈 태그/TestFlight 전환 시 체크해야 할 저장소 전용 릴리즈 가이드
- `.claude/skills/kbo-version-release/SKILL.md`
  - 앱 버전 변경, GitHub 릴리즈/태그 정리, 앱 내 패치노트 갱신 루틴
- `.claude/skills/app-startup-runtime-triage/SKILL.md`
  - 앱 시작 흰 화면, local API base URL, Dev Console 로그 노이즈, Firebase local 경고 트리아지용 가이드
- `.claude/skills/ios-device-run-action/SKILL.md`
  - 연결된 iOS 실기기 우선 실행 액션, `flutter devices`/`xcodebuild` destination 불일치 점검 가이드

## 최근 구현 인사이트
- 실기기 디버그 환경에서 `localhost` 백엔드는 신뢰하지 않는다. 모바일 디버그는 실행 스크립트가 주입하는 Mac LAN IP 기반 API 경로가 현재 원칙이다.
- 데이터 소스 혼선은 실제 장애처럼 보이므로 화면별로 다른 저장소를 보게 두지 않는다.
- 현재 허용된 direct KBO 범위:
  - `APP_ENV=local`, native runtime, `API_BASE_URL` override 없음, `PREFER_DIRECT_SCRAPE=true` 를 모두 만족하는 명시적 임시 direct-primary 빌드
  - 일반 local/dev/release 앱 모드에서는 자동 direct fallback 금지
- 기록실 선수 상세/엔트리 전체는 API 또는 생성된 snapshot 기준으로 유지한다.
- 순위/기록실 요약/리더보드는 요청 시즌과 정확히 맞는 검증된 snapshot 만 사용한다. 검증되지 않은 과거 순위는 빈 exact snapshot 으로 둔다.
- 일반 API-backed 앱 모드에서는 current-season standings / records overview / leaderboard / team players / team stats / player detail API 실패를 앱 번들 bootstrap, 구형/fresh API cache, backend current snapshot 으로 숨기지 않는다.
- Dev Console 은 현재 API base URL, API latency, 홈/일정/기록실 로딩 완료 로그, 기록실 진단 로그를 표시하는 운영 도구다.
- direct-primary 파서는 KBO 마크업 변경에 취약하므로, 수정 시 백엔드 파서와 결과를 반드시 대조한다.
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
- 주요 폰트 방향은 Pretendard(한글), SF Pro Display(영문/숫자)다
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
- 버전 변경 / GitHub 릴리즈 / 앱 내 패치노트 갱신 시: `.claude/skills/kbo-version-release/SKILL.md`
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
1. Figma 와이어프레임/주요 화면 구조 정리
2. Flutter 프로젝트 셋업
3. FastAPI 백엔드 구조 셋업
4. 크롤링 프로토타입 구축
5. 홈 스코어보드와 경기 상세 핵심 화면 구현

## Claude Skills
- `.claude/skills/bootstrap-fallback-data/SKILL.md`
  - 시즌별 standings / records overview 스냅샷 생성과 앱 fallback 연결 작업용
- `.claude/skills/app-icon-pipeline/SKILL.md`
  - 앱 아이콘 변형 제작, 선택, iOS/Android 리소스 갱신 작업용
