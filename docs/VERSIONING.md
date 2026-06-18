# Versioning And Release Policy

> Created: 2026-05-20
> Updated: 2026-06-18

## Current Baseline

- Active release line: `0.0.x`
- Flutter app version: `0.0.38+38`
- Current release tag: `0.0.38`
- Preview suffixes are not used. Do not create `*-preview*` tags or GitHub prereleases for this repository.
- Historical preview/prerelease tags were rewritten into plain numeric releases on 2026-05-20 by explicit Director request.

## Version Formats

- App version: `MAJOR.MINOR.PATCH+BUILD` in `app/pubspec.yaml`
- Git tag: `MAJOR.MINOR.PATCH`
- In-app patch note heading: app version with build, for example `0.0.28+28 - Current Boxscore & Records Guard`

## Bump Rules

- Pre-1.0 release checkpoints increment `PATCH` by one for every tester-facing or release-facing checkpoint.
- Build number increments with the app release number while this project stays in `0.0.x`.
- `MINOR` is reserved for a larger product milestone after the current early tester line is stable.
- `MAJOR` is reserved for post-1.0 product, data, or release contract changes that are incompatible with the previous stable line.
- Do not use `-preview`, `-alpha`, `-beta`, or `-rc` suffixes unless the Director explicitly changes this policy.

## Mandatory Version Checklist

Every version or release change must update these surfaces in the same work unit:

- `app/pubspec.yaml` when the app version or build number changes.
- `CHANGELOG.md` for public/user-visible release history.
- `app/assets/bootstrap/patch_notes.md` for in-app patch notes.
- GitHub Release title and body.
- `docs/WORKLOG.md` for engineering decisions and verification.
- `README.md`, `AGENTS.md`, `CLAUDE.md`, or `.claude/skills/` when release workflow rules changed.

## Release Rules

- Decide the target version before creating commits or tags.
- Tags are immutable after publish. Do not force-update, delete, or recreate published tags unless the Director explicitly approves a historical release rewrite.
- When historical releases are rewritten, update this release map, GitHub releases, in-app patch notes, and changelog in the same pass.
- GitHub releases should be normal releases, not prereleases, under the current no-preview policy.
- Mark only the newest numeric release as `Latest`.
- `APP_ENV=release` artifacts default to no-backend direct data mode and must not require the release API health gate. They should still carry the production `API_BASE_URL` for push / Live Activity token registration. Run `scripts/release-api-health-check.sh` only for explicit legacy/backend verification.
- When the Director says "이어서 해", decide autonomously whether the current work deserves a new numeric version or should only amend/rewrite the current GitHub release notes. Prefer a new version when app behavior, API behavior, user-visible UI, or in-app patch notes change.

## Numeric Release Map

- `0.0.1`: initial project scaffold, Flutter/FastAPI baseline, MVP screen skeletons.
- `0.0.2`: early run scripts, documentation, and first widget/live-activity direction cleanup.
- `0.0.3`: my-team first UX, Dynamic Island/Live Activity iteration, schedule/detail polish.
- `0.0.4`: records, player detail, game detail, and distribution baseline.
- `0.0.5`: notification, Firebase, Android/iOS signing, and tester preparation pass.
- `0.0.6`: compact scoreboard, widget/live-activity data, and API-first release guard improvements.
- `0.0.7`: final early rolling snapshot before the organized release-routine cleanup.
- `0.0.8`: release routine baseline, direct-primary path separation, release health gate, and records snapshot baseline.
- `0.0.9`: home secondary fan-out removal and API-first/direct-primary documentation cleanup.
- `0.0.10`: direct-primary historical records recovery, WebForms session handling, and startup remote prefetch removal.
- `0.0.11`: lineup tab request fan-out reduction, web resume refresh scope fix, patch-note cleanup, and current app build `0.0.11+11`.
- `0.0.12`: home KBO brief, records image fallback, wRC+ records label, home quick item player images, pre-game score hiding, app-wide micro motion, finished-game detail snapshot-first reads, and update-loop load reduction with current app build `0.0.12+12`.
- `0.0.13`: fixed KBO emblem URLs, exact-season records overview bootstrap policy, current-season team/player snapshot freshness, stale bundled records cleanup, KT 2026 snapshot refresh, and 2026 home-run leaderboard snapshot with current app build `0.0.13+13`.
- `0.0.14`: app-side device and bundled team/player snapshot freshness guard for current-season records, legacy cache envelope migration, and regression tests with current app build `0.0.14+14`.
- `0.0.15`: standings bootstrap exact-season cleanup, current-season standings freshness guard, records overview bootstrap generation from stored snapshots, selected historical records overview snapshots, stale historical standings bundle removal, web local API default hardening, and KT 2026 bundle refresh with current app build `0.0.15+15`.
- `0.0.16`: backend current-date scoreboard and current-season/month schedule, standings, records overview, and leaderboard snapshot freshness guard, app home scoreboard cache TTL, current-season records/team-player freshness cleanup, retired-player leaderboard preservation, and current app build `0.0.16+16`.
- `0.0.17`: direct KBO routing guard for local native explicit direct-primary builds only, provider/widget background API route alignment, Android/Web release API health-gated run paths, complete records-overview device snapshot guard, current API failure masking prevention, and provider routing/API cache regression tests with current app build `0.0.17+17`.
- `0.0.18`: historical backend leaderboard snapshots for 2011 ERA and 2013 HR with retired top-leader regression coverage, release-gated web wrapper, Android/Web release action wrappers, and current app build `0.0.18+18`.
- `0.0.19`: current/live game detail stale snapshot masking guards for boxscore, lineup, relay, and team records, `codex-run.sh web` release API health-gated default command, `web-dev` debug split, release execution documentation cleanup, and current app build `0.0.19+19`.
- `0.0.20`: current/future home aggregate fail-fast for schedule, standings, and records overview section failures, historical home partial fallback preservation, records overview crawler/snapshot featured canonicalization, device snapshot v3 rank-one guard for records overview/leaderboards, runtime data docs/skill alignment, and current app build `0.0.20+20`.
- `0.0.21`: app API cache validator path for records overview/leaderboards, web/API cache key invalidation for rank-gap records payloads, 2013 AVG leaderboard snapshot recovery, records overview error card, team records error messaging, app-wide provider retry disablement, and current app build `0.0.21+21`.
- `0.0.22`: current-date/current-season app API requests no longer reuse fresh local API cache after backend failure, backend current scoreboard/schedule/standings/records overview/leaderboards no longer return snapshots after crawler failure, home first paint no longer renders separate today-scoreboard local cache, 2026-05-20 cancellation/current snapshot refresh, and historical cached-first/snapshot behavior is preserved, with current app build `0.0.22+22`.
- `0.0.23`: backend current-season team players, team stats, and player detail no longer return backend snapshots or stale in-memory fallback after crawler failure, historical team/player snapshots remain available, GitHub Actions app artifacts now wait for backend pytest first, and current app build `0.0.23+23`.
- `0.0.24`: backend `/scoreboard/home` and `/scoreboard/compact` now use lightweight schedule + main list summaries without per-game scoreboard detail fan-out, full scoreboard/game detail keep detailed View1 enrichment, current home scoreboard keeps fail-visible snapshot policy, and current app build `0.0.24+24`.
- `0.0.25`: app scoreboard, relay summary, my-team card, and local KBO brief now distinguish missing H/E/B team totals from real zero values, display unavailable totals as `-` or hide that row, and current app build `0.0.25+25`.
- `0.0.26`: home secondary aggregate provider now waits until the first scoreboard data frame, home refresh timers are signature-stable across unrelated rebuilds, backend current data routes share `api/runtime_services.py` singletons to reuse TTL caches across sibling endpoints, home skeleton spacing avoids small-card overflow, and current app build `0.0.26+26`.
- `0.0.27`: LIVE home/widget summary scoreboard paths now prefer valid KBO main-list scores over schedule/detail fallback zeroes so in-progress games cannot stay at stale 0:0, with regression coverage and current app build `0.0.27+27`.
- `0.0.28`: current/live boxscore no longer borrows same-team adjacent game rows when the official payload is empty, historical adjacent canonical-id correction keeps requested `gameId` and records `sourceGameId`, records overview/leaderboards are rank-normalized before API response, with regression coverage and current app build `0.0.28+28`.
- `0.0.29`: schedule month navigation keeps selected state across selected-tab retaps and load failures, cancelled games preserve KBO status labels such as rain cancellation across app/backend/widget surfaces, direct-primary relay/boxscore player imagery and Korean name matching are tightened, relay passed-ball classification is explicit, Lotte logo uses the transparent emblem asset, and current app build `0.0.29+29`.
- `0.0.30`: TestFlight first-run crash fix for missing my-team widget storage values, iOS background refresh plist declarations for widget/push surfaces, uploaded as build `0.0.30+30` and superseded by `0.0.31`.
- `0.0.31`: push / Live Activity backend deployment preparation, immediate game-start notification defaults, iOS Workmanager BGTask launch handler registration for `kbo-widget-periodic`, direct lineup recovery through `GetLineUpAnalysis`, relay lineup labels, live my-team follow state polish, live-game ticket-info hiding, game-detail back fallback, and current app build `0.0.31+31`.
- `0.0.32`: 마이팀 live 경기 감지 시 Live Activity / Dynamic Island follow target 자동 선택, 경기 시작 기본 push topic 구독, backend `deliveryModes` topic 계산 정렬, 문자중계 focus/선수 라벨 보정, and current app build `0.0.32+32`.
- `0.0.33`: TestFlight push / Live Activity token registration build using the deployed AWS HTTP smoke backend `API_BASE_URL`, with a narrow temporary ATS exception for that ALB host, and current app build `0.0.33+33`.
- `0.0.34`: Relay foreground refresh cadence shortened to 15 seconds, game detail resume refresh keeps the last valid detail on transient failure, relay player images are reinforced from profile/current-at-bat sources, my-team live badge is shortened to `LIVE`, and current app build `0.0.34+34`.
- `0.0.35`: `at_bat` immediate push moment, relay-seq based backend homerun push, Live Activity current-at-bat payload enrichment, live boxscore placeholder guard across direct/backend paths, and current app build `0.0.35+35`.
- `0.0.36`: TestFlight iOS bundle now includes Firebase `GoogleService-Info.plist` for push initialization, API diagnostics shows release push failure reasons, backend topic resubscribe operation is documented in release notes, and current app build `0.0.36+36`.
- `0.0.37`: release/dev apps with a selected my-team now run one-time notification permission plus FCM registration sync automatically, live push/Live Activity cadence is aligned to 8 seconds, `game_start_soon` and `hit` moments are included in push topics, push registry preserves current followed game ids, Live Activity / Dynamic Island visual structure is aligned with the home score card, and current app build `0.0.37+37`.
- `0.0.38`: push moment routing polish for `game_start_soon`, explicit app/backend tests for `game_start_soon` and `hit` topic contracts, and current app build `0.0.38+38`.

## GitHub Release Note Template

```markdown
## Summary
- One or two lines explaining why this version exists.

## User-facing changes
- Feature or UX changes visible in the app.

## Data / release changes
- API, snapshot, widget, notification, or build pipeline changes.

## Verification
- Commands or checks that passed.

## Notes
- Known limits, superseded release notes, or tester instructions.
```
