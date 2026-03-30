# 작업 이력 (Work Log)

---

## 2026-03-30: 종료 경기 상세 진입 오류 수정

### 완료
- [x] 일정 화면에서 `extra` 없이 상세 화면에 진입해도 `gameId` 기반 재조회로 경기 상세를 열 수 있도록 수정
- [x] 앱 상세 화면이 `state.extra` 의존으로 바로 실패하던 흐름을 Riverpod `gameProvider` 조회 기반으로 보완
- [x] 백엔드에 누락되어 있던 `/game/{gameId}` 단건 조회 endpoint 추가
- [x] 종료 경기에서도 경기 결과/박스스코어/라인업 진입이 가능하도록 앱-백엔드 상세 조회 경로 정리
- [x] 미구현 상태인 문자중계 API가 raw 에러로 노출되지 않도록 상태별 안내 문구로 대체
- [x] 문자중계 탭이 `relay` endpoint를 중복 호출하던 구조를 단일 호출로 정리
- [x] 백엔드 `relay` endpoint가 501 대신 빈 payload를 반환하도록 정리해 웹 콘솔 오류 제거
- [x] 예정 경기 `section=START_PIT` 링크를 `SCHEDULED`로 분류하도록 일정 상태 파싱 보정
- [x] 종료 경기 문자중계 탭에서 이닝별 득점 요약과 경기 종료 결과를 보여주는 summary relay 추가

### 원인
- 홈 화면은 `/game/:gameId` 라우팅 시 `extra: game`을 넘기지만, 일정 화면은 `gameId`만 넘기고 있었음
- `GameDetailScreen`이 `game == null`이면 즉시 `경기를 찾을 수 없습니다`를 렌더링하고 있었음
- 웹/릴리즈용 `ApiGameRepository.getGame()`가 호출하는 `/game/{gameId}` 백엔드 라우트가 실제로 없었음
- `/game/{gameId}/relay`는 아직 백엔드 미구현이라 상세 탭에서 사용자에게 실패 문구가 그대로 노출되고 있었음
- 앱에서 `relayProvider`와 `currentAtBatProvider`가 같은 endpoint를 각각 호출해 같은 실패가 중복 발생하고 있었음
- KBO 일정 응답에서 예정 경기가 `section=START_PIT`로 내려오는 케이스를 `SCHEDULED`로 분류하지 못해 상세 상태가 `UNKNOWN`으로 내려오고 있었음
- KBO 공식 live relay 원본 경로를 즉시 안정적으로 확보하기 어려워, 종료 경기의 경우 scoreboard 데이터로부터 흐름 요약을 만들어 탭 공백을 줄일 필요가 있었음

---

## 2026-03-30: 예매 정보 / 예매 오픈 알림 추가

### 완료
- [x] 일정 화면 카드에 경기별 예매처와 예매 오픈 시간 표시 추가
- [x] 경기 상세 상단에 예매 정보 카드 추가
- [x] 경기 상세에서 예매처 외부 링크 열기 버튼 추가
- [x] 경기 상세에서 경기별 예매 오픈 알림 토글 추가
- [x] 디바이스 로컬 알림 기반 예매 오픈 시각 예약 알림 구현
- [x] 백엔드 `/api/schedule`, `/api/game/{gameId}`, `/api/scoreboard` 응답에 `ticketInfo` 필드 추가
- [x] 경기 상세 상단에 KBO 공식 / 유튜브 하이라이트 카드 추가
- [x] 백엔드에서 KBO 공식 링크 + 유튜브 검색 기반 `highlightInfo` 메타데이터 조회 추가
- [x] 하이라이트 카드에서 KBO 공식 페이지와 유튜브 웹 페이지를 각각 열 수 있도록 추가
- [x] 스코어 탭 이닝 셀 클릭 시 해당 회차 주요 장면 바텀시트 추가
- [x] 문자중계 탭이 라이브 경기 전용으로 막히지 않도록 완화
- [x] 라인업/상세 탭 좁은 폭 깨짐 대응을 위해 가로 스크롤 보강

### 비고
- KBO 일정 원본 응답에는 예매처/예매 오픈 시간이 없어 현재는 홈팀 기본 정책 기준 추정값으로 내려줌
- 실제 운영 단계에서는 팀별 공식 예매 페이지 크롤링 또는 별도 관리 데이터가 필요
- 웹에서는 로컬 예약 알림을 지원하지 않음

---

## 2026-03-30: 기록실 / 선수 상세 화면 추가

### 완료
- [x] 하단 탭에 `기록실` 추가
- [x] 마이팀 기준 선수 리스트 화면 추가
- [x] `전체 / 엔트리 / 엔트리 제외` 필터 추가
- [x] 선수 카드에 부상 / 엔트리 제외 상태 배지와 간단 기록 표시
- [x] 선수 프로필 / 시즌 기록 / 최근 기록을 보여주는 상세 화면 추가
- [x] 기록실에 `야수 / 투수` 탭 분리 추가
- [x] `타율 / OPS / ERA / WHIP` 기준 정렬 추가
- [x] 백엔드 `team players`, `player detail` API 추가
- [x] KBO 공식 등록 현황 / 선수 상세 기록 페이지 기반 크롤링 연결
- [x] 관련 문서(`README.md`, `CHANGELOG.md`, `docs/APP_SPEC.md`) 반영

### 비고
- 웹/릴리즈 기록실은 실제 백엔드 선수 API를 사용
- 네이티브 로컬 환경은 현재 mock fallback 유지
- KBO 공식 페이지에서 부상 사유를 직접 주지 않아 `말소 = 엔트리 제외`로 우선 표시

---

## 2026-03-30: README / CHANGELOG 정리

### 완료
- [x] 루트 `README.md` 신규 작성
- [x] 루트 `CHANGELOG.md` 신규 작성
- [x] Codex 앱 실행 액션용 `scripts/codex-run.sh` 추가
- [x] 저장소 실행 방법, 문서 우선순위, 현재 구현 범위를 루트 README에 정리
- [x] `AGENTS.md`에 README / CHANGELOG 지속 갱신 규칙 추가
- [x] `CLAUDE.md`에 README / CHANGELOG 문서 역할 및 갱신 규칙 추가
- [x] README에 Codex 앱 실행 액션 등록용 명령 추가

### 반영 원칙
- 이후 실행 방법, 현재 구현 범위, 저장소 구조가 바뀌면 `README.md`를 같이 갱신
- 이후 사용자 관점 기능 변화나 마일스톤 변화가 생기면 `CHANGELOG.md`를 같이 갱신

### 추가 수정
- [x] 백엔드 `int | None` 등 Python 3.10+ 타입 문법을 Python 3.9 호환 표기로 정리
- [x] `uvicorn` 실행 시 FastAPI import 단계에서 발생하던 타입 평가 오류 수정
- [x] `AGENTS.md`, `CLAUDE.md`에 Python 3.9 호환 타입 힌트 규칙 명시
- [x] Firebase iOS plugin 호환을 위해 iOS deployment target을 `15.0`으로 상향
- [x] Flutter web 플랫폼 추가 (`app/web`)
- [x] `scripts/codex-run.sh web` 실행 경로 추가
- [x] Codex 실행 액션용 플랫폼 분리 스크립트 추가 (`ios`, `android`, `web`)
- [x] iOS Xcode 프로젝트의 `SDKROOT` / `SUPPORTED_PLATFORMS`를 시뮬레이터 호환으로 정리

---

## 2026-03-30: AGENTS 컨텍스트 동기화

### 완료
- [x] `CLAUDE.md` 기반 `AGENTS.md` 신규 작성
- [x] 저장소 내 Markdown 문서 전체 재검토 (`CLAUDE.md`, `docs/PLANNING.md`, `docs/APP_SPEC.md`, `docs/WORKLOG.md`)
- [x] 문서 간 기준 우선순위 정리 (`AGENTS.md`에 반영)
- [x] 최신 모바일 스택 기준이 Flutter임을 재확인

### 확인 사항
- `docs/PLANNING.md` 마지막 "다음 단계" 항목의 `Expo 프로젝트 셋업` 문구를 `Flutter 프로젝트 셋업`으로 정정
- 최신 기준은 `Flutter + Dart`, `Riverpod`, `go_router`, `dio`, `FastAPI`, `AWS`, `FCM`

### 비고
- 이후 작업은 `AGENTS.md`를 기본 작업 가이드로 사용

### 추가 진행
- [x] `docs/FIGMA_PROMPT.md` 전체 검토
- [x] Figma 작업 스킬 및 대상 파일 접근 경로 확인

### 현재 블로커
- Figma MCP 조회 시 Starter 플랜 도구 호출 한도 초과로 파일 메타데이터 조회 실패
- 오류 메시지 기준 추가 작업 전 Figma MCP 한도 초기화 또는 상위 플랜 필요

### 추가 문서 정리
- [x] `docs/FIGMA_PROMPT.md` 반영해 `CLAUDE.md` 보강
- [x] `docs/FIGMA_PROMPT.md`와 최근 작업 상황 반영해 `AGENTS.md` 보강
- [x] `docs/TASK_DIVISION.md`를 협업 운영 문서 형태로 재정리

### 백엔드 착수
- [x] FastAPI 백엔드 기본 구조 생성 (`backend/`)
- [x] `pyproject.toml`, `.env.example`, `README.md` 추가
- [x] `api / core / crawlers / scheduler / push / schemas / utils` 패키지 골격 생성
- [x] `/api/health` 구현 및 나머지 제품 API 스텁 라우트 등록
- [x] 기본 테스트 파일 추가 (`backend/tests/test_health.py`)
- [x] `GetScheduleList` 기반 월간 일정 크롤러 구현
- [x] `GetScoreBoardScroll` 기반 스코어보드 상세 크롤러 구현
- [x] `GetBoxScoreScroll` 기반 박스스코어 크롤러 구현
- [x] `GetLineUpAnalysis` 기반 라인업 크롤러 구현
- [x] TeamRankDaily SSR 파싱 기반 순위 크롤러 구현
- [x] `/api/scoreboard`, `/api/schedule`, `/api/game/{gameId}/boxscore`, `/api/game/{gameId}/lineup`, `/api/standings` 연결
- [x] `/api/push/register` 성공 응답 구현

### 검증
- [x] `python3 -m compileall backend/src` 통과
- [x] 서비스 레벨에서 schedule/scoreboard/boxscore/lineup/standings 응답 샘플 확인

### 남은 백엔드 작업
- [ ] 문자중계 실제 데이터 경로 확인 및 `relay` 구현
- [ ] push/register 실제 FCM 연동 구현

---

## 2026-03-28: 프로젝트 초기 세팅 + 기획 완료

### 완료
- [x] Git 레포 생성 (godekd3133/kbo-fans, Private)
- [x] SSH 설정 (`github-personal` alias → `~/.ssh/andy` 키 → godekd3133)
- [x] `.gitignore` 작성
- [x] `CLAUDE.md` 프로젝트 컨텍스트 작성
- [x] `docs/PLANNING.md` 서비스 기획서 작성 (경쟁사 상세 분석 + 차별화 전략 포함)
- [x] `docs/APP_SPEC.md` 앱 상세 기획서 작성 (화면 6개 와이어프레임 + API 7개 명세)
- [x] `design_docs.docx` 수업 제출용 기획서 채움 (팀 정보, 기능 명세, 화면 목록, 패키지, 일정)
- [x] `docs/WORKLOG.md` 작업 이력 문서 생성

### 결정 사항
- **프레임워크**: Flutter + Dart (수업 필수 요구사항)
- **타겟 사용자**: 코어팬 + 라이트팬 모두
- **서비스 목표**: 앱스토어 출시
- **MVP 기능 4개**: 실시간 스코어보드, 문자중계, 박스스코어, 푸시 알림
- **백엔드 인프라**: AWS (EC2/ECS + RDS PostgreSQL + ElastiCache Redis)
- **상태관리**: Riverpod
- **라우팅**: go_router
- **HTTP**: dio

### 변경 이력
- React Native (Expo) → **Flutter (Dart)** 로 변경 (수업 요구사항)
- 인프라 미정 → **AWS** 로 확정
- 경쟁사 분석: 네이버 스포츠, SPORTS.i, 야구보구, ESPN 상세 분석 추가
- 차별화 전략 6가지 수립

### 파일 구조
```
kbo_fans/
├── CLAUDE.md
├── design_docs.docx
├── docs/
│   ├── PLANNING.md
│   ├── APP_SPEC.md
│   └── WORKLOG.md
```

### Figma
- 디자인 파일: https://www.figma.com/design/VZdeXTfwxJYBxy2xOJrl8c/Kbo-Fans
- Figma MCP 서버 연결 필요 (현재 미연결 상태)

### 다음 할 일
- [ ] Figma MCP 서버 연결 → 와이어프레임 직접 생성
- [ ] Flutter 프로젝트 셋업 (flutter create)
- [ ] 백엔드 프로젝트 구조 셋업 (FastAPI)
- [ ] 크롤링 프로토타입 (스코어보드 + 문자중계)
- [ ] 스코어보드 화면 구현
