# API 안내

기본 prefix는 `/api`입니다. 로컬 API는 `http://localhost:8000/api`로 접근합니다. 정확한 쿼리, 검증 조건과 payload는 해당 route와 schema, 실행 중인 서버의 `/docs`·`/openapi.json`에서 확인합니다.

## 화면 API

| Method | `/api` 다음 경로 | 용도 / 주요 입력 |
| --- | --- | --- |
| GET | `/health` | API 프로세스 기본 상태 |
| GET | `/home` | 홈 aggregate; `date`, `myTeam` |
| GET | `/scoreboard` | 전체 스코어보드; `date` |
| GET | `/scoreboard/home` | 홈 요약; `date` |
| GET | `/scoreboard/compact` | 위젯용 요약; `date`, `myTeam` |
| GET | `/game/{game_id}` | 경기 상세 |
| GET | `/game/{game_id}/relay` | 문자중계 |
| GET | `/game/{game_id}/boxscore` | 박스스코어 |
| GET | `/game/{game_id}/lineup` | 라인업 |
| GET | `/game/{game_id}/highlights` | 하이라이트 |
| GET | `/schedule` | 월 일정; 필수 `month=YYYY-MM` |
| GET | `/standings` | 순위; 필수 `season` |
| GET | `/records/overview` | 시즌 기록 요약; 필수 `season` |
| GET | `/records/leaderboard` | 지표 순위; 필수 `season`, `metric` |
| GET | `/team/{team_id}/players` | 팀 선수; 필수 `season` |
| GET | `/team/{team_id}/stats` | 팀 스탯; 필수 `season` |
| GET | `/team/{team_id}/records` | 팀 선수·스탯 묶음; 필수 `season` |
| GET | `/player/{player_id}` | 선수 상세; 필수 `season`, 선택 `player_type` |
| POST | `/metrics/client` | 클라이언트 계측 |

`date`를 생략한 스코어보드·홈은 KST 경기일을 사용합니다. 팀 ID는 KBO 내부 코드이며 `LG`, `KT`, `SK`, `SS`, `NC`, `HH`, `LT`, `HT`, `OB`, `WO`를 사용합니다. 사용자 표시명과 내부 코드를 혼동하지 않습니다.

## 응답 형식

정상 product API의 공통 envelope 예시입니다.

```json
{
  "success": true,
  "data": {},
  "error": null,
  "timestamp": "2026-10-08T00:00:00Z"
}
```

`data`의 실제 shape은 도메인별 schema를 따릅니다. upstream guard 오류는 `success=false`, `data=null`, `error.code/message`로 응답합니다. 대표 코드는 `UPSTREAM_BUSY`(503), `UPSTREAM_DEADLINE_EXCEEDED`(504)입니다. FastAPI 요청 검증 오류 등의 body는 별도 형식일 수 있으므로 모든 오류를 같은 envelope라고 가정하지 않습니다.

```bash
curl 'http://localhost:8000/api/scoreboard/home?date=2026-10-08'
curl 'http://localhost:8000/api/schedule?month=2026-10'
curl 'http://localhost:8000/api/records/overview?season=2026'
```

## 푸시 API

등록용 `POST /push/register`, `/push/live-activity/register`, `/push/live-activity/start-token/register`와 운영용 `/push/config-status`, `/push/live-activity/sync-scoreboard` 등이 있습니다. 요청 body와 보호 조건은 `api/routes/push.py`를 확인합니다. 운영 진단과 sync에는 `X-Kbo-Push-Sync-Secret`이 필요합니다. 비밀값과 실제 기기 토큰을 문서·로그·공유 명령에 기록하지 않습니다.

## 상세 문서와 소스

- [상세 계약](https://github.com/godekd3133/kbo-fans/blob/main/docs/APP_SPEC.md)
- [API route 소스](https://github.com/godekd3133/kbo-fans/tree/main/backend/src/kbo_fans_backend/api/routes)
- [응답 schema](https://github.com/godekd3133/kbo-fans/blob/main/backend/src/kbo_fans_backend/schemas/common.py)
