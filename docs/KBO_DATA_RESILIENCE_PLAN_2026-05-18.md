# KBO Data Resilience Plan - 2026-05-18

## Current Diagnosis

KBO official web sources are useful as upstream data, but they should not be on the critical path for every user screen. The fragile paths are:

- Markup-heavy pages: schedule table, boxscore, lineup, relay HTML.
- Slow aggregate pages: records, team players, player detail.
- Live-only ASMX calls: scoreboard state, current inning, score changes.

The current repository already has TTL cache, circuit breaker, server JSON snapshots, app API cache, and bundled bootstrap assets. The gap is consistency: some paths still retry direct KBO from the app or skip durable snapshots unless the game/month is fully terminal.

## Target Policy

| Data class | Examples | Runtime policy |
| --- | --- | --- |
| Live | today scoreboard, live relay, current at-bat | backend network-first, short TTL, stale fallback |
| Warm cache | today schedule, game detail, lineup before first pitch | backend cache-first after first success, quiet refresh |
| Persisted snapshot | past schedule/results, standings, records, completed boxscore/lineup/relay | snapshot-first, no request-time recrawl |
| Bundled bootstrap | standings, records overview, team players/stats | app asset fallback when backend/API cache is empty |

## Immediate Fixes Applied

- Schedule service now saves any non-empty monthly schedule payload as a snapshot, not only all-terminal months.
- Records leaderboard service now saves and reads `leaderboard/{season}:{metric}` snapshots.
- App leaderboard API fallback now uses bundled records overview data when the leaderboard endpoint and API cache are unavailable.

## Next Implementation Slices

1. Backend snapshot warmer
   - Add one command/script that warms `scoreboard`, `schedule`, `standings`, `records_overview`, `leaderboard`, `team_players`, and `team_stats`.
   - Run it manually first, then wire it to scheduler/cron later.

2. App direct-KBO kill switch
   - Keep direct KBO only for explicit local debugging.
   - Default mobile local should be `API -> app cache -> bundled asset`, not `API -> direct crawler`, except live relay/scoreboard experiments.

3. Endpoint freshness metadata
   - Add `source`, `snapshotAt`, and `stale` metadata internally for diagnostics.
   - Keep public UI simple; expose details only in Dev Console / API diagnostics.

4. Snapshot coverage tests
   - For each read path, add a failing crawler test proving snapshot/stale fallback works.
   - Priority: schedule, leaderboard, team records, boxscore, lineup, relay.

## Done Criteria

- KBO upstream outage does not blank home, schedule, standings, or records.
- Past games/details load from snapshots without recrawling.
- Live screens may degrade, but show last known state or clear live-unavailable state.
- Dev Console can identify whether data came from live, cache, snapshot, or bundled asset.
