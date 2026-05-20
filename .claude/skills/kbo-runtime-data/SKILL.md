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
- Direct KBO crawling is opt-in only when `APP_ENV=local`, native runtime, no `API_BASE_URL` override, and `--dart-define=PREFER_DIRECT_SCRAPE=true` are all true for temporary direct-primary validation builds.
- Slow detail-only payloads such as multi-highlight lookup should be lazy-loaded on a separate endpoint.
- Historical standings, records, and completed-game data should prefer snapshots when available.
- Normal API-backed app mode should not mask current-season standings / records overview / leaderboard API failures with app-bundled bootstrap data or backend current snapshots.
- Standings and records overview bootstrap fallback must be exact-season-only. Current-season standings and records overview require a fresh `generatedAt`; unverified historical seasons should remain empty instead of repeating another season.
- Current-season team players / team stats / player detail must be fresh-first and fail-visible in normal API-backed mode. Do not mask failures with backend/app/device snapshots.
- Records overview and leaderboard API caches and device snapshots must only be reused when core leaderboards start at rank 1. Bump cache keys or device snapshot versions when invalidating old malformed cache shapes.
- Backend current scoreboard, schedule, standings, records overview, and leaderboard paths must not fall back to snapshots on crawler failure. Historical dates/seasons/months may still use stored snapshots.
- Backend records overview and leaderboard responses must be normalized by ascending rank before they are cached, saved, or returned to the app.
- Backend `/home` aggregate must not mask current/future schedule, standings, or records overview failures with empty sections or placeholder cards. Historical home queries may keep partial fallback.
- App API cache must not mask current date/month/season failures. Keep `allowCacheOnFailure` default false; only historical paths should explicitly opt in to cached-first/snapshot behavior.
- Home first paint must not render a separate today-scoreboard local cache while current scoreboard API is loading. Keep current data paths latest-API-or-visible-error.
- Home secondary aggregate providers should not be watched until after the first scoreboard data frame.
- Home refresh timers should not be cancelled/restarted on unrelated rebuilds; reschedule only when interval or scoreboard signature changes.
- Backend `/scoreboard/home` and `/scoreboard/compact` should stay lightweight for first paint / widget surfaces. Do not call per-game scoreboard detail crawlers from those paths; reserve them for full scoreboard and game detail.
- Backend current data routes should share the runtime service singletons from `api/runtime_services.py` so sibling endpoints reuse the same TTL caches.
- LIVE summary scoreboard paths should prefer valid KBO main-list scores over schedule/detail fallback zeroes so in-progress games cannot stay at stale 0:0.
- Boxscore adjacent game-id fallback is historical-only. Current/live boxscore must not borrow a previous game's player rows; return the empty official-unavailable state instead.
- App UI must treat null H/E/B team totals as unavailable, not as 0 records.
- App-wide Provider retry is disabled. Surface API failures through screen error states and Dev Console logging instead of relying on automatic retries.
- Team records should load after team selection, not for every team at once.
- Home should prefer lightweight backend payloads for first paint. Do not render separate current-day local cache before the current scoreboard API resolves.
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
