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
- Codex 앱 실행 액션으로 쓰는 공용 명령은 가능하면 `scripts/` 아래 스크립트로 유지한다
- Codex 앱 실행 액션을 플랫폼별로 분리할 때는 `ios`, `android`, `web` 각각 독립 스크립트 진입점을 둔다
- 반복되는 작업은 `.claude/skills/` 로 뺄 수 있으면 빼고, 관련 진입점을 문서에 같이 남긴다
- 백엔드 최소 런타임은 `backend/pyproject.toml` 기준 Python `3.9`로 본다
- 백엔드 코드에서는 Python 3.10+ 전용 타입 문법(`int | None`, `str | None`)을 쓰지 않고 `Optional[...]`, `Union[...]`을 사용한다
- 커밋은 한글로 작성한다
- Flutter, FastAPI, Figma 산출물은 문서와 함께 같이 업데이트한다
- 화면/UX 변경 시 `docs/APP_SPEC.md`와 `docs/FIGMA_PROMPT.md` 반영 여부를 같이 확인한다

## 최근 구현 인사이트
- 실기기 디버그 환경에서 `localhost` 백엔드는 신뢰하지 않는다. 모바일 디버그는 API 우선, 일부 화면만 direct KBO fallback 허용이 현재 원칙이다.
- 데이터 소스 혼선은 실제 장애처럼 보이므로 화면별로 다른 저장소를 보게 두지 않는다.
- 현재 허용된 direct fallback 범위:
  - 홈
  - 일정
  - 순위
  - 경기 상세
- 현재 비허용 direct fallback 범위:
  - 기록실 선수 상세/엔트리 전체
  - 이 영역은 API 또는 서버 stale cache 기준으로 유지한다.
- 순위와 기록실 요약은 시즌별 스냅샷 fallback(`2001~현재`)을 앱 번들에 둔다.
- Dev Console 은 현재 API base URL, API latency, 홈/일정/기록실 로딩 완료 로그, 기록실 진단 로그를 표시하는 운영 도구다.
- 일정/순위 fallback 파서는 KBO 마크업 변경에 취약하므로, 수정 시 백엔드 파서와 결과를 반드시 대조한다.
- `.claude/skills/`에 이미 같은 작업 패턴이 있으면 먼저 그 스킬을 참고한다
- 앱 UI 카피에는 이모지를 사용하지 않는다

## 누적 인사이트
- 홈 첫 진입은 “스코어보드 우선, 나머지 섹션 후순위”가 체감 속도에 가장 중요하다
- 홈에서는 상세용 하이라이트/유튜브 검색을 절대 같이 물지 않는다
- KBO relay는 비로그인으로 안정적으로 확보되지 않으며, 로그인 세션과 재시도 정책이 필요하다
- `LiveTextView2.aspx`가 현재 타석과 play-by-play의 핵심 source다
- 라인업/박스스코어는 표보다 모바일 카드형 레이아웃이 가독성이 훨씬 좋다

## 데이터 소스
- KBO 공식 홈페이지 (koreabaseball.com) 크롤링
- 경로 1: ASP.NET SSR 페이지 → GET + BeautifulSoup
- 경로 2: ASMX 내부 API → POST → JSON
- 상세 내용은 `docs/PLANNING.md` 참조

## UX / 디자인 방향
- 모바일 기준 프레임은 390x844(iPhone 14 기준)로 본다
- 전체 방향은 모던, 미니멀, 다크 모드 기반 스포츠 앱이다
- 핵심 컬러는 다크 배경(`#0F0F0F`, `#1A1A1A`)와 라이브 강조색(`#FF4444`)다
- 팀 컬러는 개인화, 마이팀 강조, 알림/선택 상태 표현에 적극 사용한다
- 주요 폰트 방향은 Pretendard(한글), SF Pro Display(영문/숫자)다
- 공통 하단 탭은 `홈 / 일정 / 순위 / 설정` 4개 탭이다

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
- iOS 위젯 / Live Activity / Dynamic Island 수정 시: `.claude/skills/ios-live-activity-widget/SKILL.md`
- 프리뷰 릴리즈, TestFlight/Android 배포 준비 시: `.claude/skills/mobile-preview-release/SKILL.md`

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
