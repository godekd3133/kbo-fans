---
name: kbo-history-snapshot
description: Use when implementing or reviewing KBO Fans data loading, caching, or historical-data APIs. Trigger for requests about reducing loading, prefetching past records, standings snapshots, schedule/result caching, or separating live vs historical data in Flutter and FastAPI.
---

# KBO History Snapshot

## Goal

과거 데이터는 요청 시점에 다시 긁지 않고, 저장된 snapshot 을 먼저 읽게 만드는 작업용 스킬이다.

## Use This Skill When

- 사용자가 "로딩 없이 바로 보이게", "미리 받아와서 캐싱", "지난 경기/순위/선수 기록 snapshot" 같은 요구를 할 때
- 홈/일정/순위/기록실/선수 상세의 체감 속도 개선이 목표일 때
- live 데이터와 historical 데이터를 같은 방식으로 처리하고 있어 구조 분리가 필요할 때

## Data Freshness Rules

- `Live`
  - 진행 중 경기 scoreboard, relay, 현재 타석, 당일 라인업 변경
  - 짧은 TTL + polling
- `Warm Cache`
  - 오늘 일정, 경기 단건 상세, 직전 경기 boxscore
  - TTL cache + prefetch
- `Persisted Snapshot`
  - 선수 과거 기록, 지난 경기 결과, 지난 날짜 순위
  - snapshot 우선 조회

## Backend Workflow

1. 대상 endpoint/service 가 어느 계층인지 먼저 분류한다.
2. historical 또는 terminal data 면 service 계층에 snapshot 저장/조회 fallback 을 둔다.
3. crawler 는 원천 파싱만 맡기고, cache/snapshot/stale fallback 은 service 에 둔다.
4. 경기 종료 시점에 저장 가능한 데이터는 boxscore, lineup, relay summary, season aggregate 순으로 본다.
5. Python 3.9 호환 타입 문법을 유지한다.
6. 구현 후 관련 테스트를 추가한다.

## App Workflow

1. 히스토리성 GET 은 cached-first 로 읽고 background refresh 를 건다.
2. live 경로는 network-first 를 유지하되 stale fallback 은 허용한다.
3. snapshot 이 있으면 로딩 스피너 대신 마지막 성공 데이터를 먼저 보여준다.

## Files To Check

- `docs/APP_SPEC.md`
- `docs/ENGINEERING_NOTES.md`
- `backend/src/kbo_fans_backend/services/*`
- `app/lib/data/api/api_client.dart`
- `app/lib/data/repositories/*`

## Validation

- `cd backend && source .venv/bin/activate && pytest -q`
- `cd app && fvm flutter analyze --no-fatal-infos`
- 필요하면 실제 API 응답 시간 비교를 남긴다.
