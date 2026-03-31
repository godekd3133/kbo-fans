---
name: kbo-asmx-direct-integration
description: Use when the Flutter app calls KBO ASMX endpoints directly and you need to fix request params, plain-text JSON decoding, or table-row parsing for schedule and scoreboard flows.
---

# KBO ASMX Direct Integration

## When To Use

- `app/lib/data/repositories/kbo_direct_repository.dart` 수정 시
- KBO ASMX direct path 에서 `500`, 타입 캐스트, mixed payload 이슈가 날 때
- native local debug 경로가 backend API 없이 KBO source 를 직접 읽을 때

## Rules

- `GetScheduleList`는 아래 파라미터를 기본으로 쓴다.
  - `leId=1`
  - `srIdList=0,9,6`
  - `seasonId={YYYY}`
  - `gameMonth={MM}`
  - `teamId=''`
- `yearMonth` / `srId` 조합은 쓰지 않는다.
- Dio 에서 바로 `Map<String, dynamic>`로 받지 않는다.
  - `ResponseType.plain`
  - `jsonDecode`
  순으로 처리한다.
- `rows[].row[]` 테이블 구조와 구형 field 구조 둘 다 fallback 으로 받는다.

## Known Failure Patterns

- `type 'String' is not a subtype of type 'Map<String, dynamic>?'`
  - JSON 문자열을 Dio generic decode 에 바로 맡겼을 때
- `KBO FAIL /ws/Schedule.asmx/GetScheduleList`
  - 잘못된 request shape
  - KBO side temporary 500
  - date / month param mismatch

## Validation

- Python `requests`로 endpoint shape 먼저 확인
- app dev console 에서 `KBO OK /ws/Schedule.asmx/GetScheduleList` 확인
- `getSchedule('2026-03')`
- `getScoreboard('2026-03-31')`
