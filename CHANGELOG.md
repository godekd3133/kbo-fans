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

### Changed

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
- 디바이스 로컬 예약 알림으로 예매 오픈 시각 알림을 받을 수 있게 보완
- 경기 상세 API에서 KBO 공식 하이라이트 링크와 유튜브 검색 기반 메타데이터를 함께 내려주도록 확장
- 문자중계 API 미구현 상태에서 상세 탭에 raw 오류가 노출되지 않도록 경기 상태별 안내 문구로 정리
- 문자중계 탭의 중복 API 호출을 제거하고, relay API가 빈 응답을 반환하도록 정리해 웹 콘솔 오류를 줄임
- KBO 일정의 `START_PIT` 프리뷰 링크를 예정 경기로 인식하도록 보정해 예정 경기 상세 상태가 `UNKNOWN`으로 내려오지 않게 수정
- 종료 경기 문자중계 탭에 이닝별 득점 흐름과 최종 결과를 보여주는 summary relay를 추가

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
