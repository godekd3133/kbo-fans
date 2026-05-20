---
name: kbo-runtime-data
description: Use when changing KBO data-loading paths, deciding between backend API and direct crawler usage, tuning cache/snapshot behavior, or validating scoreboard/records/standings runtime flows in this repository.
---

# KBO Runtime Data

## When to use
- Home, schedule, standings, records, or game detail data path changes
- Cache, prefetch, or snapshot policy changes
- Web/local/release environment routing changes
- Runtime performance or first-paint regressions

## Rules
- Web and release builds should go through backend API paths.
- Local native debugging should go through backend API paths by default.
- Direct KBO crawling is opt-in only with `--dart-define=PREFER_DIRECT_SCRAPE=true` for temporary direct-primary validation builds.
- Slow detail-only payloads such as multi-highlight lookup should be lazy-loaded on a separate endpoint.
- Historical standings, records, and completed-game data should prefer snapshots when available.
- Standings and records overview bootstrap fallback must be exact-season-only. Current-season standings require a fresh `generatedAt`; unverified historical seasons should remain empty instead of repeating another season.
- Current-season team player/team stat fallback must be timestamped and fresh. Reject timestamp-less legacy device caches and stale bundled bootstrap assets instead of showing old records.
- Backend current-date scoreboard and current-season/month schedule, standings, records overview, and leaderboard snapshot fallback must require a fresh `savedAt`; historical dates/seasons/months may still use stored snapshots.
- Team records should load after team selection, not for every team at once.
- Home should prefer lightweight/cached data for first paint, then refresh in background.
- Never block `runApp()` on non-critical platform plugin initialization.

## Validation
- App: `cd app && fvm flutter analyze`
- App: `cd app && fvm flutter test`
- Backend: `python3 -m compileall backend/src`
- Backend tests: `backend/.venv/bin/pytest -q`
- Spot-check live endpoints with `curl` or `python3 - <<'PY' ... urllib.request ...`

## Common repo paths
- App env routing: `app/lib/core/config/app_config.dart`
- App providers: `app/lib/data/providers.dart`
- Direct KBO path: `app/lib/data/repositories/kbo_direct_repository.dart`
- Home runtime flow: `app/lib/features/home/home_screen.dart`
- Records runtime flow: `app/lib/features/records/records_screen.dart`
- Scoreboard API: `backend/src/kbo_fans_backend/api/routes/scoreboard.py`
- Player/team records API: `backend/src/kbo_fans_backend/api/routes/teams.py`
- Snapshots: `backend/data/snapshots/`
