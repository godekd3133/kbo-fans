# Changelog

이 문서는 사용자 입장에서 의미 있는 저장소 변경 사항을 기록합니다.

형식 원칙:

- 날짜 기준 역순 기록
- 사용자에게 보이는 기능/구조 변화 위주 기록
- 세부 작업 로그는 `docs/WORKLOG.md`에서 관리

## [Unreleased]

### Added

- 루트 `README.md` 추가
- 루트 `CHANGELOG.md` 추가
- Codex 앱 실행 액션용 `scripts/codex-run.sh` 추가
- 문서 유지관리 규칙에 `README.md`와 `CHANGELOG.md` 갱신 원칙 추가
- Flutter web 플랫폼 추가 (`app/web`)

### Changed

- 저장소 소개, 실행 방법, 문서 우선순위를 루트 README에서 바로 확인할 수 있도록 정리
- README에 Codex 앱 실행 액션 등록용 공용 명령 추가
- `scripts/codex-run.sh`에 Chrome 기반 웹 실행 명령 추가
- 에이전트/프로젝트 컨텍스트 문서에 README 및 CHANGELOG 지속 갱신 규칙 반영
- 백엔드 타입 힌트를 Python 3.9 호환 문법으로 정리해 `uvicorn` 실행 오류 수정
- Firebase iOS 플러그인 요구사항에 맞춰 iOS 최소 배포 버전을 `15.0`으로 상향

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
