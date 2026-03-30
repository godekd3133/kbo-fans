# KBO Fans

KBO Fans는 KBO 프로야구 팬을 위한 모바일 앱입니다.  
iOS와 Android를 대상으로 하며, 오늘 경기 스코어보드와 마이팀 중심 경험을 빠르게 보여주는 것을 목표로 합니다.

## Overview

- App: Flutter + Dart
- Backend: Python FastAPI
- State management: Riverpod
- Navigation: go_router
- HTTP: dio
- Infra target: AWS
- Push: Firebase Cloud Messaging

## Current Scope

MVP Phase 1 기준 핵심 범위:

- 오늘 경기 스코어보드
- 경기 상세
  - 스코어
  - 문자중계
  - 박스스코어
  - 라인업
  - KBO 공식 + 유튜브 하이라이트 연결
- 기록실
  - 팀 엔트리
  - 엔트리 제외 / 부상 이탈
  - 선수 프로필 / 최근 기록
  - 투수 / 야수 탭 분리
  - 타율 / OPS / ERA / WHIP 정렬
- 마이팀 선택
- 일정
  - 경기별 예매처 / 예매 오픈 시간 표시
  - 경기 상세에서 예매처 바로가기 / 예매 오픈 알림
- 순위
- 푸시 알림
 - 홈/잠금화면 위젯 연동 준비

현재 `app/`은 Flutter 프로젝트로 생성되어 있으며, 주요 화면 구조와 라우팅, 다크 테마, 일정/기록실/경기 상세가 포함되어 있습니다.  
`backend/`는 FastAPI 골격과 스코어보드/일정/박스스코어/라인업/순위, 팀 선수 기록 API가 준비되어 있습니다.

## Repository Structure

```text
kbo_fans/
├── README.md
├── CHANGELOG.md
├── AGENTS.md
├── CLAUDE.md
├── docs/
│   ├── APP_SPEC.md
│   ├── FIGMA_PROMPT.md
│   ├── PLANNING.md
│   ├── TASK_DIVISION.md
│   └── WORKLOG.md
├── app/
└── backend/
```

## Documentation Priority

- Repository working rules: `AGENTS.md`
- High-level product/project context: `CLAUDE.md`
- Product goals and MVP scope: `docs/PLANNING.md`
- Screen behavior and API contracts: `docs/APP_SPEC.md`
- Visual system and Figma composition: `docs/FIGMA_PROMPT.md`
- Latest decisions and work history: `docs/WORKLOG.md`
- External-facing project summary and setup guide: `README.md`
- User-visible release history: `CHANGELOG.md`

문서 간 충돌 시 최신 결정은 `CLAUDE.md`, `docs/WORKLOG.md`, 실제 코드 기준으로 판단합니다.

## Run The App

Flutter SDK가 설치되어 있다는 전제입니다.

```bash
cd app
flutter pub get
flutter run
```

플랫폼 지정 예시:

```bash
flutter run -d ios
flutter run -d android
```

참고:

- 현재 저장소에는 `ios/`와 `android/` 프로젝트가 모두 포함되어 있습니다.
- `web/`과 `macos/`는 아직 생성되지 않았습니다.
- 현재 홈 화면은 일부 목데이터를 사용하므로, UI 확인만 목적이면 백엔드 없이도 실행 가능합니다.
- 예매 오픈 알림은 앱 로컬 예약 알림으로 동작합니다. 현재 예매처/오픈 시간은 홈팀 기본 정책 기준 추정값입니다.
- 위젯 갱신은 앱 foreground에서는 라이브 30초 / 예정 5분 기준으로 반영되며, 백그라운드 주기는 OS 정책에 따라 제한됩니다.

Codex 앱에서 바로 실행할 수 있도록 공용 스크립트도 추가했습니다.

```bash
./scripts/codex-run.sh ios
./scripts/codex-run.sh android
./scripts/codex-run.sh web
./scripts/codex-run.sh backend
./scripts/codex-run.sh doctor
```

권장 등록 방식:

- iOS 실행 액션: `./scripts/codex-run-ios.sh`
- Android 실행 액션: `./scripts/codex-run-android.sh`
- Web 실행 액션: `./scripts/codex-run-web.sh`
- Backend 실행 액션: `./scripts/codex-run.sh backend`
- 환경 점검 액션: `./scripts/codex-run.sh doctor`

플랫폼별 실행 환경을 분리한 Codex 액션용 래퍼:

```bash
./scripts/codex-run-ios.sh
./scripts/codex-run-android.sh
./scripts/codex-run-web.sh
```

## Run The Backend

```bash
cd backend
python3 -m venv .venv
source .venv/bin/activate
pip install -e ".[dev]"
uvicorn kbo_fans_backend.main:app --reload
```

기본 확인 엔드포인트:

- `GET /api/health`

## Design And Product Principles

- 앱을 열면 바로 야구 정보를 보여준다
- 마이팀 중심 경험을 우선한다
- 다크 테마 기반 스포츠 앱 톤을 유지한다
- 과도한 포털형 정보 나열보다 빠른 확인 경험을 우선한다

## Notes

- KBO 공식 소스 크롤링에 의존하므로 파서와 수집 경로는 변경에 취약할 수 있습니다.
- 라이브 경기 데이터는 적응형 폴링 전략을 전제로 설계합니다.
- 상세 설계와 상태 코드는 `docs/APP_SPEC.md`를 우선 참고합니다.

## Maintenance Rule

이 저장소에서 의미 있는 기능 변경, 문서 기준 변경, 실행 방법 변경이 발생하면 아래 문서들을 함께 갱신합니다.

- `README.md`
- `CHANGELOG.md`
- `docs/WORKLOG.md`
- 필요 시 `AGENTS.md`, `CLAUDE.md`, `docs/APP_SPEC.md`, `docs/FIGMA_PROMPT.md`
