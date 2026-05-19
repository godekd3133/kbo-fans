# KBO Data Refresh Architecture - 2026-05-19

## Purpose

KBO Fans must stop treating every baseball data request the same way. Some data must be live, but most data should not be recrawled on every screen entry. This document defines how to split live data and snapshot data, how to prevent repeated crawling, and where current app screens appear to over-fetch.

## Core Decision

Use four data classes:

| Class | Examples | Source policy | App policy |
| --- | --- | --- | --- |
| Live | today scoreboard, live score, inning, count, current at-bat, live relay | backend network-first, short TTL, stale fallback | refresh only while visible; show last known state when stale |
| Warm cache | today schedule, game summary, pre-game lineup, near-game boxscore shell | backend cache-first after first success, quiet refresh | cached-first; do not block first paint |
| Persisted snapshot | past schedule/results, final game summary, final boxscore, final lineup, final relay summary, standings by date, season records | snapshot-first; recrawl only by scheduled warmer/manual repair | render immediately; background refresh only when explicitly allowed |
| Bundled bootstrap | standings fallback, records overview, team players/stats assets | app asset fallback after API/cache failure | never hit KBO directly for stable data |

The app should not use direct KBO crawling as a normal fallback. Direct KBO should be an explicit local debug mode only.

## Backend Boundary

The backend owns upstream access:

```text
App -> API route -> Service -> Cache/Snapshot policy -> Crawler -> KBO upstream
```

Crawler classes should only parse upstream data. They should not decide freshness, retries, snapshot fallback, or UI-specific payload shape.

Service classes should decide:

- whether an endpoint is live, warm, or snapshot-first
- TTL and stale fallback
- whether to save a snapshot
- whether to serve a partial payload
- whether a crawler call is allowed at request time

## Freshness Matrix

| Endpoint/data | Class | TTL | Snapshot | Request-time crawler allowed |
| --- | --- | --- | --- | --- |
| `/scoreboard/home?date=today` | Live | 30s | save when historical or terminal day | yes |
| `/scoreboard/home?date=past` | Persisted snapshot | none | required if available | no by default |
| `/game/{gameId}` live | Live | 30s | stale game snapshot allowed | yes |
| `/game/{gameId}` final/past | Persisted snapshot | none | required if available | no by default |
| `/game/{gameId}/relay` live | Live | 10-20s or `afterSeqNo` | stale detailed relay allowed | yes |
| `/game/{gameId}/relay` final | Persisted snapshot | none | detailed relay or summary snapshot | no by default |
| `/game/{gameId}/boxscore` live | Warm cache | 60s | stale allowed | yes, but not from unrelated tabs |
| `/game/{gameId}/boxscore` final | Persisted snapshot | none | required if available | no by default |
| `/game/{gameId}/lineup` pre/live | Warm cache | 1-5m before/early game | stale allowed | yes |
| `/game/{gameId}/lineup` final | Persisted snapshot | none | required if available | no by default |
| `/schedule?month=current` | Warm cache | 5m | save any non-empty month payload | yes |
| `/schedule?month=past` | Persisted snapshot | none | required if available | no by default |
| `/standings?season=current` | Warm cache | 5m | latest + daily snapshot | yes, but not from unrelated detail tabs |
| records overview/leaderboard | Persisted snapshot | 5m app cache | snapshot + bundled asset fallback | no by default after warm |
| team players/stats/records | Persisted snapshot | 5m app cache | snapshot + bundled asset fallback | no by default after warm |

## Required Metadata

Every backend service response should eventually carry internal freshness metadata:

```json
{
  "source": "live|cache|stale_cache|snapshot|bootstrap|summary",
  "fetchedAt": "2026-05-19T10:00:00+09:00",
  "snapshotAt": "2026-05-19T09:58:00+09:00",
  "stale": false,
  "ttlSeconds": 30
}
```

UI does not need to show all of this. Dev Console and API diagnostics should.

## Repeated Crawling Controls

### Backend

Add a shared `DataFetchCoordinator` around service calls:

- `singleflight`: identical key in flight returns the same future/result.
- `rate limit`: each upstream key has minimum spacing.
- `circuit breaker`: already exists in `BaseCrawler`, but should be paired with stale/snapshot response.
- `stale-while-revalidate`: serve stale immediately, refresh in background where safe.
- `request budget`: one screen/API endpoint should not trigger broad unrelated crawlers.

Recommended keys:

```text
scoreboard:2026-05-19
schedule:2026-05
game:20260519LGOB0
relay:20260519LGOB0
boxscore:20260519LGOB0
lineup:20260519LGOB0
standings:2026
records_overview:2026
leaderboard:2026:avg
team_records:LG:2026
```

### App

Keep Riverpod providers as the in-app dedupe layer, but avoid creating extra providers for data the current screen does not need.

Rules:

- Live refresh invalidates only live providers.
- Stable providers use `getCached(... preferCache: true)`.
- Screen preloading must have a strict budget.
- Image preloading must not load all teams when two teams are enough.
- Pull-to-refresh may bypass cache, but normal screen entry should not.

## Current Over-Fetch Review

## Evidence Map

This review is based on the current code paths below:

| Area | Evidence |
| --- | --- |
| Repository routing | `app/lib/data/providers.dart:37-56` builds `ApiGameRepository` and `KboDirectRepository`; non-web API failure still falls back to direct KBO. |
| Home aggregate fan-out | `app/lib/data/providers.dart:202-239` reads scoreboard, two months of schedule, standings, and records overview. |
| All-player image map | `app/lib/data/providers.dart:265-300` loops through all 10 teams and calls `getTeamPlayers` for each team. |
| Home fallback fan-out | `app/lib/features/home/home_screen.dart:372-430` can watch aggregate, two schedules, and standings in one section. |
| Home preload | `app/lib/features/home/home_screen.dart:596-613` preloads scoreboard games through `GameDetailPreloadService`. |
| Home live polling | `app/lib/features/home/home_screen.dart:1040-1058` refreshes live home scoreboard every 10s. |
| Schedule preload | `app/lib/features/schedule/schedule_screen.dart:74-91` preloads up to 3 game details from schedule. |
| Detail broad refresh | `app/lib/features/game_detail/game_detail_screen.dart:196-214` invalidates game, relay, boxscore, and lineup together. |
| Score tab relay dependency | `app/lib/features/game_detail/tabs/score_tab.dart:22-35` watches `relayDataProvider`. |
| Relay tab broad player data | `app/lib/features/game_detail/tabs/relay_tab.dart:44-74` watches game, relay, two team player lists, and all-player image map. |
| Lineup tab broad data | `app/lib/features/game_detail/tabs/lineup_tab.dart:52-84` watches lineup, boxscore-derived batters/pitchers, relay, two team player lists, all-player image map, standings, two schedules, and two team stats. |
| Widget background direct path | `app/lib/services/widget_sync_service.dart:25-37` background task creates a repository and fetches scoreboard; `app/lib/services/widget_sync_service.dart:58-60` currently returns `KboDirectRepository`. |
| Alert relay path | `app/lib/services/game_event_alert_service.dart:86-101` loops tracked games, and `app/lib/services/game_event_alert_service.dart:151-169` fetches relay per live tracked game. |
| Direct KBO queue/dedupe | `app/lib/data/repositories/kbo_direct_repository.dart:38-45` has request maps/queue; `app/lib/data/repositories/kbo_direct_repository.dart:96-115` serializes network calls. |
| Direct scoreboard fan-out | `app/lib/data/repositories/kbo_direct_repository.dart:277-315` gets schedule, main game map, and per-game scoreboard/detail calls. |
| Backend game route fan-out | `backend/src/kbo_fans_backend/api/routes/games.py:24-76` calls both scoreboard and schedule for a single game. |
| Backend highlight route | `backend/src/kbo_fans_backend/api/routes/games.py:79-102` may fetch YouTube for non-scheduled games. |
| Backend team records fan-out | `backend/src/kbo_fans_backend/api/routes/teams.py:27-52` calls team players and team stats in parallel. |
| Backend scoreboard fan-out | `backend/src/kbo_fans_backend/services/scoreboard.py:53-113` calls schedule, main game list, and per-game enrich in parallel. |
| Backend game snapshot behavior | `backend/src/kbo_fans_backend/services/scoreboard.py:138-145` returns game snapshot first, otherwise calls date scoreboard. |

## Detailed Findings

### P0 Finding 1 - Direct KBO is still a normal app fallback

Current:

- `gameRepositoryProvider` uses `FallbackGameRepository(primary: apiRepository, fallback: directRepository)` when `preferDirectScrape` is false.
- `AppConfig` currently defaults `preferDirectScrape` to true for local non-web native builds.
- `WidgetSyncService.createRepositoryForBackground()` always returns `KboDirectRepository`.

Why this is a problem:

- A backend/API outage should not automatically multiply into direct KBO crawling from every client.
- Widget background refresh can hit KBO independently from the visible app.
- Direct repository contains local relay credentials as constants; this should not be a normal runtime path.

Decision:

- Direct KBO must become explicit debug-only.
- Native local default should be API-first with app cache/bootstrap fallback, not direct KBO.
- Widget background should use the same app/API cache path or a compact backend widget endpoint.

### P0 Finding 2 - Home first paint is protected, but second wave is too wide

Current:

- First content starts with `scoreboardProvider(today)`, which is good.
- The secondary wave can call aggregate, schedule, previous schedule, standings, records overview, and detail preload.
- If a live game exists, home refresh interval is 10s.

Why this is a problem:

- A 10s home scoreboard refresh can repeatedly trigger alert processing and widget sync.
- Secondary content may already be covered by `/home`, but fallback starts separate provider calls.
- Detail preload can turn a home visit into relay/boxscore/lineup/team player work.

Decision:

- Home first paint remains scoreboard-only.
- `/home` aggregate is the only allowed secondary network call.
- Fallback should use already-loaded cache only; it should not launch a fresh schedule/standings/overview fan-out.
- Detail preload should be opt-in or limited to one selected live my-team game.

### P0 Finding 3 - Detail refresh invalidates unrelated tabs

Current:

- `_refreshGameDetail()` invalidates game, relay, boxscore, and lineup together.
- It runs on initial entry, resume, and timer.
- Live interval is 30s.

Why this is a problem:

- If user is on Score tab, boxscore and lineup should not refresh.
- If user is on Relay tab, lineup should not refresh every 30s.
- If user is on Lineup tab, relay and boxscore should not be mandatory unless the tab explicitly uses decorations.

Decision:

- Track active tab.
- Header refresh updates `gameProvider`.
- Relay tab owns relay polling.
- Boxscore tab owns boxscore polling.
- Lineup tab owns lineup polling.
- Shared refresh should not invalidate all detail providers.

### P0 Finding 4 - Score tab should not require relay

Current:

- `ScoreTab` watches `relayDataProvider` only to support inning-scene context.

Why this is a problem:

- Score view should be the cheapest detail tab.
- Relay is one of the most fragile live sources.

Decision:

- Score tab uses `Game` inning scores only.
- Add `inningSummary` later if scoring-event jump is needed.
- Relay loads only when Relay tab is visible or user taps an inning action that requires relay.

### P0 Finding 5 - Lineup tab is doing too much

Current:

- Lineup tab watches 13 data surfaces: lineup, away/home batters, away/home pitchers, relay, away/home players, all-player image map, standings, current schedule, previous schedule, away/home team stats.

Why this is a problem:

- A lineup view becomes a dashboard aggregator.
- It can trigger records/schedule/relay/boxscore paths just by opening one tab.
- It couples stable snapshot data and live data in one widget build.

Decision:

- Split UI into:
  - `lineupProvider`: lineup only.
  - `matchupSummaryProvider`: cached/snapshot summary built by backend.
- Remove `allPlayerImageMapProvider` from this tab.
- Do not fetch schedule/standings/team stats directly from Lineup tab.

### P1 Finding 6 - `allPlayerImageMapProvider` is too expensive for live tabs

Current:

- The provider loops 10 teams and calls `getTeamPlayers` for each.
- Relay and Lineup tabs use it as a fallback image map.

Why this is a problem:

- One live tab can trigger all-team records/player data.
- This violates screen request budget.

Decision:

- Build image maps from only two game teams.
- Prefer image URLs from relay/lineup/boxscore payloads.
- Keep all-player map only for offline records browsing or explicit warmup jobs.

### P1 Finding 7 - Backend `/game/{gameId}` calls scoreboard and schedule

Current:

- `get_game` calls `scoreboard_service.get_game(game_id)` and `schedule_service.get_schedule_game(game_id)`.
- `scoreboard_service.get_game` may call date scoreboard when no game snapshot exists.

Why this is a problem:

- A single game detail header can trigger full date scoreboard enrichment.
- Schedule is also queried separately for ticket/highlight info.

Decision:

- Add a compact `GameSummaryService.get_game_summary(game_id)` that reads game snapshot first, schedule snapshot second, and only crawls live scoreboard when the game is today/live.
- Avoid full date scoreboard enrichment for past/final detail headers.

### P1 Finding 8 - Alerts and widgets are separate refresh surfaces

Current:

- Home data triggers local alert processing.
- Widget background creates direct repository and fetches scoreboard.
- Widget sync may fetch current at-bat after receiving games.

Why this is a problem:

- Visible app, local alert, widget, and Live Activity can each become their own refresh loop.
- They should share a single latest scoreboard/current-at-bat cache.

Decision:

- Introduce `LiveDataCoordinator` in app.
- Home, alerts, widgets, and Live Activity read from the same latest app cache.
- Background widget refresh uses backend compact endpoint or last cached app payload, not direct KBO by default.

### P1 Finding 9 - Backend needs request budgets per endpoint

Current:

- `ScoreboardService.get_scoreboard` can call schedule, main game list, and per-game scoreboard detail.
- `HomeService.get_home` calls scoreboard plus schedule/standings/overview.
- `TeamRecords` calls players and stats together.

Why this is a problem:

- Fan-out is not wrong by itself, but it needs declared budget and source class.
- Without a budget, UI changes can accidentally expand upstream crawling.

Decision:

- Every route should declare:
  - max upstream calls
  - max total timeout
  - fallback behavior
  - allowed data classes
  - whether crawler calls are allowed for past/stable data

Recommended budgets:

| Endpoint | Max upstream budget |
| --- | --- |
| `/scoreboard/home?date=today` | schedule 1, main list 1, detail only for live/final visible cards |
| `/home` | no new crawler if scoreboard/schedule/standings/overview stale cache exists |
| `/game/{gameId}` | 0 for final snapshot hit; 1 compact live lookup for live/today |
| `/game/{gameId}/relay` | 1 relay request, optional scoreboard fallback from cache only |
| `/game/{gameId}/boxscore` | 1 boxscore request; no schedule lookup unless canonical id repair needed |
| `/game/{gameId}/lineup` | 1 lineup request; no boxscore request except fallback starter fill |
| `/team/{teamId}/records` | 0 crawler after snapshot exists; scheduled warmer owns refresh |

### Home

Current flow:

- `HomeScreen` watches `scoreboardProvider(today)`.
- Secondary content watches `homeAggregateProvider(today|myTeam)`.
- If aggregate errors, fallback watches `scheduleProvider(currentMonth)`, `scheduleProvider(previousMonth)`, and `standingsProvider(season)`.
- Overview section may separately watch `recordsOverviewProvider(season)`.
- Home also schedules detail preload for up to 3 games.

Risk:

- Home can load scoreboard, aggregate, schedule, standings, records overview, game detail, relay, boxscore, lineup, and team players close together.
- This is too much for first screen.

Target:

- First paint: `scoreboard/home` only.
- Secondary: `/home` aggregate only, after first paint.
- Fallback: local cached aggregate or local calculation from already-loaded data; do not start broad fallback fetches automatically.
- Detail preload: only my-team live game or tapped game; no top-3 broad preload by default.

### Schedule

Current flow:

- `ScheduleScreen` watches `scheduleProvider(yearMonth)`.
- It preloads up to 3 selected games through `GameDetailPreloadService`.

Risk:

- Opening a month can immediately trigger game detail, relay, boxscore, lineup, and team player preloads.
- Schedule screen mostly needs month/date/game-card fields, not game-detail tabs.

Target:

- Schedule screen loads only monthly schedule.
- Preload only on user intent: tap, long hover not relevant on mobile, or visible my-team live game.
- Past month should be snapshot-only.

### Game Detail

Current flow:

- Detail screen watches `gameProvider(gameId)`.
- Initial post-frame preload warms relay, boxscore, lineup, and player images.
- Refresh timer invalidates `gameProvider`, `relayDataProvider`, `gameBoxscoreProvider`, and `gameLineupProvider`.
- Live interval: 30s. Scheduled interval: 5m.

Risk:

- During live games, boxscore and lineup are refreshed every 30s even if the visible tab is Score or Relay.
- Lineup rarely needs 30s refresh.
- Boxscore does not need to refresh when user is not on Boxscore tab.

Target:

- Base detail header: `gameProvider`.
- Score tab: game summary only, or an inning-summary endpoint; do not require full relay.
- Relay tab: `relayDataProvider`, 10-20s visible-only polling.
- Boxscore tab: `gameBoxscoreProvider`, 60s visible-only polling for live; snapshot-first for final.
- Lineup tab: `gameLineupProvider`, 1-5m visible-only polling until lineup is published; no polling after final.

### Score Tab

Current flow:

- Watches `relayDataProvider` just to make inning table cells jump to relay scenes.

Risk:

- Score tab can trigger relay crawling even when user only wants score/table.

Target:

- Score tab should not fetch full relay by default.
- Add a small `gameTimelineSummary` or use game inning scores only.
- Load relay only when user taps a scoring inning or opens Relay tab.

### Relay Tab

Current flow:

- Watches `gameProvider`, `relayDataProvider`, away/home `teamPlayersProvider`, and `allPlayerImageMapProvider`.

Risk:

- Relay screen may load all teams' player image map, not just current game participants.
- Team player loads are stable data and should not be coupled to live relay polling.

Target:

- Relay API returns current at-bat image URLs and participant IDs where possible.
- Relay tab loads only two teams' cached players as fallback.
- Remove `allPlayerImageMapProvider` from live relay path.

### Boxscore Tab

Current flow:

- Uses `battersProvider` and `pitchersProvider`, both derived from the same `gameBoxscoreProvider`.
- Also watches `relayDataProvider`, `gameLineupProvider`, and selected `teamPlayersProvider`.

Risk:

- Boxscore tab can trigger relay and lineup loads even if only batter/pitcher table is needed.
- Derived batters/pitchers are okay because they share the boxscore provider, but refresh paths should invalidate the source provider only once.

Target:

- Boxscore table: `gameBoxscoreProvider` only.
- Player images: selected team cached players only.
- Relay/lineup context should be optional decoration and should not block content.

### Lineup Tab

Current flow:

- Watches lineup, both teams' batters/pitchers, relay, both teams' players, all-player image map, standings, current and previous schedule, and both teams' stats.

Risk:

- This is the heaviest screen-level over-fetch.
- A lineup tab should not cause schedule, standings, team stats, boxscore, relay, and all-player image crawling by default.

Target:

- Split into two payloads:
  - `lineup`: starter + lineup list.
  - `matchupSummary`: standings rank, recent games, team stats, starter comparison.
- Backend builds `matchupSummary` from snapshots/caches.
- Lineup tab watches only `lineupProvider` and `matchupSummaryProvider`.

### Records

Current flow:

- Team chooser watches `recordsOverviewProvider`.
- Team records screen watches `teamRecordsProvider` and `standingsProvider`.
- Refresh invalidates both.

Risk:

- Mostly acceptable because team selection gates team data.
- Standing lookup for every team records screen should be included in `teamRecords` or a compact team-rank field to avoid a second endpoint.

Target:

- Team records endpoint includes `teamStanding` snapshot.
- Leaderboard detail uses metric-specific snapshot.

## Proposed Target Architecture

### Backend Service Types

```python
class DataClass:
    LIVE = "live"
    WARM_CACHE = "warm_cache"
    SNAPSHOT = "snapshot"
    BOOTSTRAP = "bootstrap"
```

Each service method should declare:

- data class
- cache key
- TTL
- snapshot namespace/key
- upstream crawler permission
- stale fallback permission

### App Provider Types

```text
Live providers:
- scoreboardProvider(today)
- gameProvider(live game)
- relayDataProvider(live game)

Warm providers:
- scheduleProvider(currentMonth)
- gameBoxscoreProvider(live game)
- gameLineupProvider(pre/live game)

Snapshot providers:
- scheduleProvider(pastMonth)
- standingsProvider
- recordsOverviewProvider
- leaderboardProvider
- teamRecordsProvider
- playerDetailProvider
```

## Implementation Plan

### P0 - Stop obvious repeated work

- Make `preferDirectScrape` default false for native local; enable only with `--dart-define=PREFER_DIRECT_SCRAPE=true`.
- Remove app-side direct KBO fallback from default `FallbackGameRepository`; use API cache/bootstrap fallback instead.
- Move direct relay credentials out of source and into local secure config if direct debug mode remains.
- Change widget background refresh to use API/cache-backed repository or a compact backend endpoint.
- Change game detail refresh to invalidate providers by visible tab.
- Remove full detail preload from schedule screen.
- Limit home detail preload to one my-team live game.
- Remove `allPlayerImageMapProvider` from Relay/Lineup live paths.
- Make Score tab independent from `relayDataProvider`.

### P1 - Backend contracts for screen-specific data

- Add `/game/{gameId}/matchup-summary`.
- Add `/game/{gameId}/inning-summary` or include inning event summary in game payload.
- Add `/widget/scoreboard` or `/scoreboard/compact` for widget/Live Activity.
- Add `GameSummaryService.get_game_summary(game_id)` to avoid full date scoreboard fan-out on detail header loads.
- Add metadata fields internally: `source`, `stale`, `fetchedAt`, `snapshotAt`, `ttlSeconds`.
- Add singleflight/rate-limit coordinator around upstream crawler calls.
- Add route-level request budgets and tests that fail if stable/past endpoints invoke crawlers.

### P2 - Snapshot warmer

- Add one script/job to warm:
  - today scoreboard
  - current month schedule
  - standings latest/daily
  - records overview
  - leaderboard metrics
  - team players/stats/records
  - final game boxscore/lineup/relay summary
- Scheduler owns repeated crawling. User requests do not.

## Verification Plan For Implementation

To move this from design to code, use measurable checks:

1. Add a dev-only request counter around `ApiClient` and `KboDirectRepository`.
2. For each screen, log provider names and cache source:
   - Home cold start
   - Schedule month open
   - Game detail Score tab
   - Game detail Relay tab
   - Game detail Lineup tab
   - Records team chooser
3. Write backend unit tests with failing crawlers:
   - past scoreboard returns snapshot without crawler
   - final game detail returns game/schedule snapshot without full scoreboard crawl
   - final boxscore/lineup/relay returns snapshot
   - records/team endpoints return snapshot/bootstrap fallback
4. Add app tests or dev diagnostics for provider fan-out:
   - Schedule screen must not call detail preload on normal entry
   - Score tab must not read relay provider
   - Lineup tab must not read all-team image map

## Expected Request Count After P0

| User action | Current risk | Target request count |
| --- | --- | --- |
| Open Home | scoreboard + aggregate + fallback providers + detail preload | 1 critical API call, 1 deferred aggregate |
| Open Schedule | schedule + up to 3 detail preloads | 1 schedule API call |
| Tap Game Detail Score tab | game + preload + relay + boxscore + lineup | 1 game summary call |
| Switch to Relay tab | relay + two team players + all-player map | 1 relay call, optional two-team cached player lookup only |
| Switch to Boxscore tab | boxscore + relay + lineup + team players | 1 boxscore call, optional selected-team cached players |
| Switch to Lineup tab | lineup + boxscore + relay + standings + two schedules + team stats + players + all-player map | 1 lineup call + 1 cached matchup summary |
| Widget background refresh | direct KBO scoreboard + current at-bat | 1 compact API/cache call |

## Done Criteria

- Home first paint requires only scoreboard/home.
- Schedule screen never triggers game-detail crawlers on normal entry.
- Detail refresh only updates visible live data.
- Stable records/standings/schedule data can render while KBO upstream is down.
- Dev Console can show `source` and stale state.
- Backend tests cover crawler failure fallback for every stable endpoint.

## 2026-05-19 P0 Implementation Status

Applied in app code:

- `preferDirectScrape` now defaults to `false` on native local builds. Direct KBO scraping is opt-in only with `--dart-define=PREFER_DIRECT_SCRAPE=true`.
- Default `gameRepositoryProvider` no longer wraps API with direct KBO fallback. Normal app mode now uses API-backed data only.
- Default `playerRepositoryProvider` no longer falls back to direct player crawling. It falls back to generated/local asset player data after API/snapshot failure.
- Widget background sync now uses `ApiGameRepository(ApiClient())` by default and only uses `KboDirectRepository` in explicit direct debug mode.
- Startup prefetch was reduced to first-screen API payloads: today scoreboard, current month schedule, standings, records overview, and my-team home/records when configured.
- Startup no longer warms all-player image maps, all team records, all historical seasons, every game detail, every boxscore, every lineup, every relay, player details, or bulk image files.
- Home and Schedule no longer trigger game-detail preloads on normal list entry or row tap.
- Game Detail no longer preloads every tab on entry. Initial entry refreshes only the game summary, and timed/pull refresh only invalidates the visible tab's provider.
- `GameDetailPreloadService` was removed so the old broad detail warmer cannot be reintroduced accidentally through an existing service call.
- Score tab no longer reads `relayDataProvider`.
- Relay and Lineup tabs no longer read `allPlayerImageMapProvider`.
- `api_home_repository.dart` now parses `HomeRecentGameSummary.gameId`, fixing the analyzer error exposed during this pass.

Still intentionally left for P1:

- `LineupTab` still reads relay data for bullpen/order enrichment.
- `BoxscoreTab` still reads relay/lineup/team-player data for richer post-game cards.
- Backend still needs route-level request budget tests, singleflight/rate-limit coordination, and compact widget/detail endpoints.

Verification:

- `fvm dart format` on touched Dart files passed.
- `fvm flutter analyze` passed with no issues.
- `fvm flutter test test/widget_test.dart test/data/models/records_overview_test.dart test/services/push_notification_service_test.dart` passed.

## 2026-05-19 P1 Backend Implementation Status

Applied in backend code:

- Added process-local `SingleFlight` utility to coalesce concurrent identical work by key.
- `ScoreboardService.get_scoreboard(date)` now wraps uncached date loads with `singleflight`, so concurrent same-date requests share one schedule/main/enrich pass.
- `ScoreboardService.get_game(gameId)` no longer calls `get_scoreboard(date)` and no longer enriches every game on that date for one detail request.
- `ScoreboardService.get_game(gameId)` now:
  - checks game snapshot first
  - checks short TTL game cache
  - loads the date schedule
  - selects only the requested game
  - loads main game metadata once
  - enriches only that requested game
- `/api/game/{gameId}` no longer calls `ScheduleService.get_schedule_game()` when `ScoreboardService.get_game()` already returned a game payload.
- Added `/scoreboard/compact`, a widget/Live-surface endpoint that selects at most one relevant game and enriches only that game instead of building the full daily scoreboard payload.
- Relay service tests now use an isolated temporary snapshot store where the test expects synthetic summary fallback, avoiding accidental coupling to local real relay snapshots.

Applied in app code:

- Widget background refresh now calls `/scoreboard/compact` through `ApiGameRepository.getCompactScoreboard()` in normal API mode.
- Widget background refresh still allows `KboDirectRepository` only when explicit direct debug mode is enabled.
- Widget sync no longer fetches relay/current-at-bat data, so a widget update does not become a separate relay crawl.
- Live Activity sync no longer creates `KboDirectRepository` internally for current-at-bat fallback; it uses the already supplied game payload and leaves batter/pitcher/count empty until a backend-owned compact live payload exists.
- Push topic tests were updated to match the v4 delivery model: only `immediate` Moments subscribe to direct push topics.

Request impact:

- Repeated simultaneous Home/scoreboard opens for the same date should hit upstream at most once per process while the first request is in flight.
- Game Detail Score tab's `/game/{gameId}` path no longer fans out to all same-day game detail enrich calls.
- Schedule fallback lookup for `/game/{gameId}` only runs when the scoreboard/game summary path cannot find the game.
- Widget background refresh requests at most one compact scoreboard game and no longer performs a relay/current-at-bat request.
- Live Activity updates no longer perform direct KBO current-at-bat fallback from the client.

Verification:

- `backend/.venv/bin/python -m compileall backend/src` passed.
- `backend/.venv/bin/pytest -q backend/tests/test_scoreboard_service_cache.py backend/tests/test_games.py backend/tests/test_snapshot_services.py` passed.
- `backend/.venv/bin/pytest -q` passed: 42 tests.
- `fvm dart format` on touched app files passed.
- `fvm flutter analyze` passed with no issues.
- `fvm flutter test test/widget_test.dart test/data/models/records_overview_test.dart test/services/push_notification_service_test.dart` passed.

Live measurement on 2026-05-19:

| Path | Result | Elapsed | Upstream calls |
| --- | --- | --- | --- |
| `get_home_scoreboard(2026-05-19)` cold | 5 games | 349ms | schedule 1, main list 1, game detail 5, view1 detail 5 |
| `get_home_scoreboard(2026-05-19)` cached | 5 games | ~0ms | no additional upstream calls |
| `get_compact_scoreboard(2026-05-19, LG)` cold | 1 game | 313ms | schedule 1, main list 1, game detail 1, view1 detail 1 |
| `get_compact_scoreboard(2026-05-19, LG)` cached | 1 game | ~0ms | no additional upstream calls |

Measured impact: compact refresh reduces widget/Live-surface detail enrichment from 5 games to 1 game for this date. Wall-clock latency is similar on this run because full scoreboard enrich runs in parallel, but upstream request volume and failure surface are lower.

Still left after this P1 slice:

- Add route-level request-budget middleware/counters for dev diagnostics.
- Split Lineup/Boxscore enrichment endpoints so those tabs do not need relay/team-player side reads for first paint.
- Add cross-process dedupe/rate limiting if deployed with multiple workers.
- Add a backend-owned compact live state payload if Live Activity must show batter/pitcher/B-S-O without client direct crawling.
