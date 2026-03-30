# KBO Fans 작업 분담 & 협업 운영 문서

> 최종 수정: 2026-03-30
> 목적: Claude Code와 Codex가 같은 저장소에서 병렬 작업할 때, 해야 할 일/맥락/경계/진행 상태를 한 문서로 공유하기 위한 기준서

---

## 1. 이 문서의 역할

- 이 문서는 **실시간 협업용 단일 기준 문서**다.
- 각 에이전트는 작업 시작 전 이 문서를 먼저 읽고, 자기 작업의 상태/범위/산출물을 확인한다.
- 작업 분담의 목표는 다음 3가지다.
  - 작업 누락 방지
  - 중복 구현 방지
  - 문서/코드/API 계약 불일치 방지

### 문서 우선순위

1. `AGENTS.md`: 저장소 전반 작업 규칙
2. `docs/TASK_DIVISION.md`: 실시간 협업 분담/상태/경계
3. `docs/APP_SPEC.md`: 화면 상세와 API 계약
4. `docs/FIGMA_PROMPT.md`: Figma 시안/와이어프레임 기준
5. `docs/PLANNING.md`: 제품 목표와 로드맵
6. `docs/WORKLOG.md`: 작업 이력

문서 간 충돌이 생기면:
- 구현 경계/협업 규칙은 `AGENTS.md`, `docs/TASK_DIVISION.md`
- 화면/데이터 계약은 `docs/APP_SPEC.md`
- 최신 결정 사항은 `docs/WORKLOG.md`

---

## 2. 프로젝트 맥락 요약

- 앱: KBO 프로야구 실시간 경기 정보 모바일 앱
- 플랫폼: iOS / Android
- 모바일 스택: Flutter + Dart
- 앱 구조: Riverpod / go_router / dio
- 백엔드 스택: FastAPI + Python
- 인프라: AWS (EC2 또는 ECS, RDS PostgreSQL, ElastiCache Redis)
- 푸시: Firebase Cloud Messaging
- 데이터 소스: KBO 공식 웹 페이지 + ASMX 내부 API
- 디자인 기준: `docs/FIGMA_PROMPT.md`

### 제품 방향

- "앱을 열면 바로 야구"가 핵심 UX 원칙이다.
- 코어팬에게는 문자중계/박스스코어/라인업의 깊이를 제공한다.
- 라이트팬에게는 마이팀 중심 빠른 확인 경험을 제공한다.
- 디자인 방향은 모던, 미니멀, 다크 모드 기반 스포츠 앱이다.

### 현재 디자인 기준

- 기본 모바일 프레임: `390x844`
- 공통 탭: `홈 / 일정 / 순위 / 설정`
- 핵심 화면:
  - 온보딩
  - 홈 스코어보드
  - 경기 상세 4탭
  - 일정
  - 순위
  - 설정
  - 위젯

---

## 3. 현재 협업 원칙

### 최상위 분담 원칙

- Claude Code는 **앱 프론트엔드와 런타임 UX**를 담당한다.
- Codex는 **백엔드, 크롤링, API 계약 구현, 협업 문서 유지**를 담당한다.
- Figma는 별도 축으로 보되, 실제 Figma MCP가 막히면 문서 기준 정합성 유지가 우선이다.

### 디렉토리 소유권

#### Claude Code 소유

- `app/`
- Flutter 관련 설정 파일
- 앱 테마, 라우팅, UI 컴포넌트, 화면, 앱 서비스 계층

#### Codex 소유

- `backend/`
- `docs/TASK_DIVISION.md`
- 백엔드/크롤링/서버 관련 문서 보강

#### 공동 편집 가능

- `docs/APP_SPEC.md`
- `docs/FIGMA_PROMPT.md`
- `docs/WORKLOG.md`
- `CLAUDE.md`
- `AGENTS.md`

### 공동 편집 파일 규칙

- 공동 파일은 한 번에 한 에이전트만 주도적으로 수정한다.
- 공동 파일 수정 시:
  - 왜 수정하는지
  - 어떤 계약이 바뀌는지
  - 상대 작업에 영향이 있는지
  를 명확히 남긴다.

---

## 4. 절대 겹치면 안 되는 작업

### Claude Code가 하지 않는 일

- `backend/` 하위 구현
- KBO 크롤러 로직 작성
- FastAPI 엔드포인트 서버 구현
- 서버 스케줄러/푸시 발송 로직 구현

### Codex가 하지 않는 일

- `app/` 하위 Flutter 화면 구현
- Flutter 테마/라우터/provider 구현
- 온보딩/홈/상세/일정/순위/설정의 실제 UI 코드 작성

### 예외

- API 계약이 바뀌는 경우
- 공통 문서의 최신화가 필요한 경우
- 사용자가 명시적으로 재배치 지시를 준 경우

---

## 5. 현재 작업 분담표

### Claude Code 담당

| ID | 작업 | 상태 | 선행조건 | 소유 경로 | 완료 기준 |
|---|---|---|---|---|---|
| C1 | Flutter 프로젝트 셋업 | 🔄 진행중 | 없음 | `app/` | 앱 실행 가능한 기본 구조 생성 |
| C2 | 앱 공통 구조 구축 | ⬜ 대기 | C1 | `app/lib/core/` | theme/router/provider 골격 정리 |
| C3 | 온보딩 화면 구현 | ⬜ 대기 | C2 | `app/lib/features/onboarding/` | 팀 선택 2상태 반영 |
| C4 | 홈 스코어보드 구현 | ⬜ 대기 | C2, X6-M1 | `app/lib/features/home/` | 라이브/예정/빈 상태 UI 완료 |
| C5 | 경기 상세 4탭 구현 | ⬜ 대기 | C4, X6-M2 | `app/lib/features/game_detail/` | 4탭 UI + 탭 전환 완료 |
| C6 | 일정 화면 구현 | ⬜ 대기 | C2, X6-M3 | `app/lib/features/schedule/` | 월간 캘린더 + 경기 목록 UI 완료 |
| C7 | 순위 화면 구현 | ⬜ 대기 | C2, X6-M4 | `app/lib/features/standings/` | 순위 테이블 UI 완료 |
| C8 | 설정 화면 구현 | ⬜ 대기 | C2 | `app/lib/features/settings/` | 마이팀/알림/앱정보 UI 완료 |
| C9 | 앱 API 연동 | ⬜ 대기 | C2, X6 | `app/lib/data/` | dio client + DTO/Repository 연결 |
| C10 | FCM 앱 연동 | ⬜ 대기 | C8, X10 | `app/lib/services/push/` | 토큰 등록 및 기본 흐름 연결 |

### Codex 담당

| ID | 작업 | 상태 | 선행조건 | 소유 경로 | 완료 기준 |
|---|---|---|---|---|---|
| X1 | FastAPI 프로젝트 셋업 | ✅ 완료 | 없음 | `backend/` | 앱 실행 가능한 FastAPI 골격 |
| X2 | 스코어보드 크롤러 | ✅ 완료 | X1 | `backend/crawlers/scoreboard.py` | scoreboard 응답 스키마 충족 |
| X3 | 문자중계 크롤러 | ⬜ 대기 | X1 | `backend/crawlers/relay.py` | relay 응답 스키마 충족 |
| X4 | 박스스코어/라인업 크롤러 | ✅ 완료 | X1 | `backend/crawlers/boxscore.py`, `backend/crawlers/lineup.py` | boxscore/lineup 스키마 충족 |
| X5 | 일정/순위 크롤러 | ✅ 완료 | X1 | `backend/crawlers/schedule.py`, `backend/crawlers/standings.py` | schedule, standings 구현 완료 |
| X6 | REST API 구현 | 🔄 진행중 | X2~X5 | `backend/api/` | scoreboard, schedule, boxscore, lineup, standings 연결 완료 / relay, push 대기 |
| X7 | Adaptive Polling 설계 | ⬜ 대기 | X2 | `backend/scheduler/` | 경기 상태별 폴링 정책 정의 |
| X8 | 변경 감지/중복 방지 | ⬜ 대기 | X2~X5 | `backend/utils/` | hash 또는 diff 기반 감지 |
| X9 | 선수 기록 크롤러 | ⬜ 대기 | X1 | `backend/crawlers/player_stats.py` | 팀 선수 기록 조회 가능 |
| X10 | 푸시 이벤트 서버 | 🔄 진행중 | X6, X7 | `backend/push/` | register 응답 구현 완료 / 실제 FCM 발송 대기 |
| X11 | 협업 문서 관리 | 🔄 진행중 | 없음 | `docs/` | 분담 문서 최신 상태 유지 |

### Figma 축

| ID | 작업 | 상태 | 소유 | 산출물 | 비고 |
|---|---|---|---|---|---|
| F1 | User Flow | ⬜ 대기 | 미정 | Page 0 | 문서 기준 있음 |
| F2 | 온보딩 | ⬜ 대기 | 미정 | Page 1 | 2상태 |
| F3 | 홈 스코어보드 | ⬜ 대기 | 미정 | Page 2 | 3상태 |
| F4 | 경기 상세 4탭 | ⬜ 대기 | 미정 | Page 3~6 | 핵심 화면 |
| F5 | 일정/순위/설정 | ⬜ 대기 | 미정 | Page 7~9 | 보조 화면 |
| F6 | 위젯 | ⬜ 대기 | 미정 | Page 10 | Phase 1.5 |

---

## 6. 병렬 작업 전략

### 지금 바로 병렬 가능한 작업

#### Claude Code

- C1 Flutter 프로젝트 셋업
- C2 공통 앱 골격 설계
- C3 온보딩 화면

#### Codex

- X1 FastAPI 골격
- X2 스코어보드 크롤러
- X3 문자중계 크롤러
- X11 협업 문서 유지

이 구간은 서로 파일 경로와 실행 환경이 분리돼 있어 충돌 가능성이 낮다.

### Mock 우선 전략

- Claude Code는 X6 완성 전에도 `docs/APP_SPEC.md` 응답 형식 기준으로 mock 데이터로 UI를 먼저 구현할 수 있다.
- Codex는 UI 구현과 무관하게 API 스키마를 먼저 고정하고 서버를 맞춰간다.

### 마일스톤 기반 핸드오프

#### X6-M1

- `/api/scoreboard`
- 홈 화면 연동 시작 가능

#### X6-M2

- `/api/game/{gameId}/relay`
- `/api/game/{gameId}/boxscore`
- `/api/game/{gameId}/lineup`
- 경기 상세 4탭 연동 시작 가능

#### X6-M3

- `/api/schedule`
- 일정 화면 연동 시작 가능

#### X6-M4

- `/api/standings`
- 순위 화면 연동 시작 가능

#### X6-M5

- `/api/push/register`
- `/api/team/{teamId}/players`
- 설정/알림/선수 요약 연동 가능

---

## 7. API 공유 계약

> 상세 계약은 `docs/APP_SPEC.md`를 따른다. 이 문서는 협업 관점에서 꼭 필요한 요약만 둔다.

| Endpoint | Method | 프론트 선행 작업 | 백엔드 담당 |
|---|---|---|---|
| `/api/scoreboard?date={YYYY-MM-DD}` | GET | 홈 스코어보드 | X2, X6 |
| `/api/game/{gameId}/relay?after={seqNo}` | GET | 문자중계 탭 | X3, X6 |
| `/api/game/{gameId}/boxscore` | GET | 박스스코어 탭 | X4, X6 |
| `/api/game/{gameId}/lineup` | GET | 라인업 탭 | X4, X6 |
| `/api/schedule?month={YYYY-MM}` | GET | 일정 화면 | X5, X6 |
| `/api/standings?season={YYYY}` | GET | 순위 화면 | X5, X6 |
| `/api/team/{teamId}/players?season={YYYY}` | GET | 선수 요약/Phase 1.5 | X9, X6 |
| `/api/push/register` | POST | 설정/푸시 등록 | X10, X6 |

### gameId 형식

```text
YYYYMMDD + 어웨이팀코드 + 홈팀코드 + 더블헤더(0)
예: 20260328KTLG0
```

### 팀 코드

- `LG`
- `KT`
- `SK` = SSG
- `SS` = 삼성
- `NC`
- `HH` = 한화
- `LT` = 롯데
- `HT` = KIA
- `OB` = 두산
- `WO` = 키움

---

## 8. Codex 백엔드 구현 맥락

### 데이터 소스

#### SSR HTML

- `https://www.koreabaseball.com/Schedule/ScoreBoard.aspx`
- `https://www.koreabaseball.com/Game/LiveText.aspx?gameId={ID}&gyear={YEAR}`
- `https://www.koreabaseball.com/Schedule/Schedule.aspx`

#### ASMX API

- `/ws/Schedule.asmx/GetScoreBoardScroll`
- `/ws/Schedule.asmx/GetBoxScoreScroll`
- `/ws/Schedule.asmx/GetRelayData`
- `/ws/Schedule.asmx/GetMatchPlayerList`
- `/ws/Schedule.asmx/GetScheduleList`

### POST 공통 파라미터

```text
leId: 1
srId: 0
seasonId: 2026
gameId: "20260328KTLG0"
```

### 요청 헤더

```text
Content-Type: application/x-www-form-urlencoded; charset=UTF-8
X-Requested-With: XMLHttpRequest
Referer: https://www.koreabaseball.com/
User-Agent: desktop browser UA
```

### Codex 구현 원칙

- 파싱 로직과 응답 매핑 로직을 분리한다.
- KBO 마크업 변경 가능성을 고려해 selector를 한 곳에 모은다.
- API 응답 스키마는 프론트 친화적으로 정규화한다.
- 크롤러 테스트용 fixture를 남길 수 있으면 남긴다.

---

## 9. Claude Code 프론트엔드 구현 맥락

### 화면 구현 우선순위

1. 온보딩
2. 홈 스코어보드
3. 경기 상세 4탭
4. 일정
5. 순위
6. 설정

### 프론트 구현 원칙

- 초기 단계는 mock 데이터 우선 허용
- UI 상태는 최소한 아래 3종을 고려:
  - loading
  - error
  - empty or no-game
- 숫자/스코어 표기는 문서 기준을 유지
- 팀 컬러는 마이팀 강조와 상태 표시에만 선택적으로 강하게 사용

### Codex가 건드리지 않는 프론트 범위

- 화면 layout
- widget tree
- 앱 테마/폰트/spacing
- 앱 라우팅
- Riverpod provider 설계

---

## 10. Figma 작업 맥락

### 기준 문서

- `docs/FIGMA_PROMPT.md`

### 현재 상태

- Figma MCP 접근은 계정/권한 또는 플랜 한도 이슈가 있었다.
- 따라서 Figma 캔버스 직접 작업은 아직 완료된 것으로 간주하지 않는다.
- 그 전까지는 문서 기준만 최신 상태로 유지한다.

### Figma가 막혀 있을 때의 대체 전략

- Claude Code는 `docs/FIGMA_PROMPT.md`를 기준으로 UI를 구성한다.
- Codex는 Figma 실작업 대신 문서 정합성 유지와 화면 상태 정의 보강을 맡는다.

---

## 11. 상태 업데이트 규칙

### 상태 값

- `⬜ 대기`
- `🔄 진행중`
- `✅ 완료`
- `⛔ 블로커`

### 갱신 규칙

1. 작업 시작 직전: 상태를 `🔄 진행중`으로 바꾼다.
2. 블로커 발생 시: `⛔ 블로커`와 원인을 적는다.
3. 완료 시: `✅ 완료`와 산출물 경로를 적는다.
4. 공동 계약이 바뀌면:
   - `docs/APP_SPEC.md`
   - `docs/WORKLOG.md`
   - 필요 시 `CLAUDE.md`, `AGENTS.md`
   를 함께 업데이트한다.

---

## 12. 충돌 방지 체크리스트

- 작업 전에 내가 수정할 경로가 내 소유 범위인지 확인했는가
- 공동 문서를 수정하면 상대 작업 영향도를 확인했는가
- API 응답 형식을 바꾸면 `docs/APP_SPEC.md`를 같이 바꿨는가
- 완료 기준이 문서에 적혀 있는가
- 블로커가 생기면 문서에 남겼는가

---

## 13. 현재 진행 상황

### 완료된 공통 작업

- 기획 문서 작성
- `CLAUDE.md` 작성 및 보강
- `AGENTS.md` 작성 및 보강
- `docs/FIGMA_PROMPT.md` 작성
- 협업 문서 초안 작성

### Claude Code 현재

- `C1` Flutter 프로젝트 셋업 진행중
- FVM + Flutter 설치/환경 준비 진행중

### Codex 현재

- `X1` FastAPI 프로젝트 골격 생성 완료
- `X2` 스코어보드 크롤러 구현 완료
- `X4` 박스스코어/라인업 크롤러 구현 완료
- `X5` 일정/순위 크롤러 구현 완료
- `X6`에서 scoreboard/schedule/boxscore/lineup/standings API 연결 완료
- `X11` 협업 문서 유지 진행중
- Figma MCP 접근 불가 이슈 확인 완료
- 다음 작업은 `X3` 문자중계 경로 추적과 `X10` 실제 FCM 발송 설계

### 현재 블로커

- Figma MCP가 파일 접근 권한 또는 플랜 이슈로 안정적으로 동작하지 않음

---

## 14. 다음 행동 제안

### Claude Code 다음

1. `C1` 완료
2. `C2` 공통 앱 구조 생성
3. `C3` 온보딩 mock UI 착수

### Codex 다음

1. `X1` FastAPI 프로젝트 골격 생성
2. `X3` 문자중계 크롤러 구현
3. `X3` 문자중계 경로 구현
4. `X6-M4`까지 API 최소 세트 제공

### 공동

1. Figma 접근 상태가 풀리면 `F1~F6` 재시도
2. API 스키마가 바뀌면 즉시 `docs/APP_SPEC.md` 동기화
