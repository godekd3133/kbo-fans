# KBO Fans Agent Guide

## Project Summary
- KBO Fans is a mobile app for KBO baseball fans on iOS and Android.
- The current agreed stack is Flutter + Dart for the app and Python FastAPI for the backend.
- Main data comes from KBO official sources via crawling and internal API calls, then is re-served through the backend.

## Source Of Truth
- Start with this file for repository-level working rules.
- Use `CLAUDE.md` for high-level project context.
- Use `.claude/SKILL_REFERENCE.md` for reusable task patterns extracted from prior work.
- Use `README.md` for external-facing project summary, quick start, and local preview/run guidance.
- Use `CHANGELOG.md` for user-visible change history.
- Use `docs/VERSIONING.md` for app version, Git tag, GitHub release, and patch-note policy.
- Use `docs/DISTRIBUTION_GUIDE.md`, `docs/ANDROID_SIGNING_GUIDE.md`, and `docs/IOS_TESTFLIGHT_CHECKLIST.md` for friend/tester distribution work.
- Use `docs/APP_SPEC.md` for screen behavior, provider structure, API contracts, and status codes.
- Use `docs/ENGINEERING_NOTES.md` for implementation-level insights, local/dev behavior, widget/live activity constraints, and release workflow notes.
- Use `docs/PLANNING.md` for product goals, MVP scope, UX principles, and risk context.
- Use `docs/FIGMA_PROMPT.md` for visual system, frame sizing, dark theme rules, page ordering, and wireframe/detail screen composition.
- Use `docs/WORKLOG.md` for recent decisions and change history.
- When documents conflict, prefer the newest decision recorded in `CLAUDE.md` and `docs/WORKLOG.md`.

## Current Product Scope
- MVP Phase 1 centers on scoreboard, relay, box score, lineup, push notifications, my team selection, schedule, and standings.
- Primary target users are KBO core fans and light fans, with "my team first" UX as a core product principle.
- The app should feel fast, lightweight, and baseball-focused rather than like a generic sports portal.
- Phase 1.5 already has explicit widget concepts in the specs, so widget-related design or data decisions should not be treated as out of scope by default.

## Working Rules
- Record meaningful work in Markdown under `docs/`.
- Append ongoing work history to `docs/WORKLOG.md`.
- Keep `README.md` updated when setup steps, local preview flow, repository structure, or current implementation scope changes.
- Keep `CHANGELOG.md` updated when user-visible features, architecture milestones, or developer-facing setup behavior changes.
- Keep shared local run entrypoints under `scripts/` stable when they are used as Codex app execution actions.
- Prefer one action entrypoint per platform when Codex app execution actions are split by environment (`ios`, `android`, `web`).
- When work becomes repeatable, prefer documenting it under `.claude/skills/` and keep AGENTS/CLAUDE aligned with the new skill entrypoints.
- Keep feature or task context as Markdown documents under `docs/` when the work is large enough to need durable context.
- Use Korean commit messages.
- Keep implementation aligned with Flutter, Riverpod, go_router, dio, FastAPI, AWS, and FCM unless the user explicitly changes direction.
- When changing UX flows, screen states, or navigation, update both the relevant spec doc and the work log in the same task when feasible.
- Treat design artifacts as first-class project context, not secondary references.
- Codex app action commands created in the repo still require manual registration in the app UI; do not assume scripts auto-populate the action menu.

## Runtime Notes
- Web and release builds should use backend API paths, not direct KBO ASMX/HTML calls.
- Local native runs should use backend API paths by default. Direct KBO crawling is opt-in only when `APP_ENV=local`, native runtime, no `API_BASE_URL` override, and `PREFER_DIRECT_SCRAPE=true` are all true for temporary direct-primary validation builds.
- Home first paint should prefer lightweight/cached payloads, then refresh in the background.
- Historical standings, records, and finished-game detail should prefer stored snapshots when available over re-crawling upstream pages.
- Team records UX should enter through team selection first, then fetch team-specific records after selection.
- If `origin` SSH access fails during push, use the repository SSH alias path `git@github-personal:godekd3133/kbo-fans.git`.

## Repo Skills
- Reusable repo-local workflows live under `.claude/skills/`.
- Skill index lives in `.claude/SKILL_REFERENCE.md`.
- `kbo-runtime-data`: use when changing app data-loading paths, cache/snapshot policy, API vs direct KBO routing, or performance-sensitive record/scoreboard flows.
- `kbo-history-snapshot`: use when classifying live vs historical data, adding snapshot-first backend paths, or making app historical screens cached-first.
- `kbo-doc-sync`: use when architecture/API/UX changes also require synced updates across AGENTS, CLAUDE, spec docs, worklog, changelog, and skills.
- `kbo-release-flow`: use when preparing commits, pushes, numeric release tags, or friend/TestFlight-facing release steps for this repository.
- `kbo-version-release`: use when changing app versions, creating/reworking GitHub releases, or updating in-app patch notes.
- If the Director says `이어서 해`, continue autonomously and decide from the actual diff whether to create the next numeric release or only reinforce the current GitHub Release notes.

## Implementation Insights
- Keep app data sources consistent by domain. Do not let one screen use mock data while another uses live API for the same product surface.
- For mobile debug builds on real devices, `localhost` API assumptions are unsafe. Use the run scripts so `API_BASE_URL` is injected as the Mac LAN IP.
- Current fallback policy:
  - Direct KBO must not be used as an automatic fallback in normal app mode.
  - Direct KBO is allowed only for explicit temporary direct-primary builds where `APP_ENV=local`, native runtime, no `API_BASE_URL` override, and `PREFER_DIRECT_SCRAPE=true` are all true, including API-not-yet-implemented validation paths such as `ios-local-release`.
  - Records must stay API-backed or generated snapshot-backed. Do not silently fall back to incomplete mock data there.
  - In normal API-backed app mode, current-season standings / records overview / leaderboard failures must surface as API failures instead of being masked by app-bundled bootstrap data. Backend API may use fresh server snapshots internally.
  - Standings and records overview bootstrap fallback must be exact-season-only. Current-season standings and records overview require a fresh `generatedAt`, and unverified historical seasons must stay empty instead of repeating another season.
  - Current-season team player/team stat fallback must require a fresh `savedAt` timestamp. Reject timestamp-less legacy device caches and stale bundled assets instead of showing old season-start records.
  - Records overview and leaderboard API caches and device snapshots must start at rank 1 before they can be saved or reused. Bump cache keys or device snapshot versions when invalidating malformed cached shapes.
  - Backend current-date scoreboard and current-season/month schedule, standings, records overview, and leaderboard snapshot fallback must require a fresh `savedAt`; historical dates/seasons/months may still use stored snapshots.
  - Backend `/home` aggregate must not hide current/future schedule, standings, or records overview failures behind empty sections or placeholder cards. Historical home queries may keep partial fallback.
- App-wide Provider retry is intentionally disabled. Do not depend on Riverpod automatic retries to hide API failures; surface errors in screen state and log technical detail to Dev Console.
- When touching direct KBO parsers in `app/lib/data/repositories/kbo_direct_repository.dart`, keep field parity with backend contracts. Schedule status, scores, and standings parsing have already drifted once and broke UI state.
- Dev-only diagnostics should stay in Dev Console when possible. Avoid promoting debugging affordances to user-facing UI unless explicitly requested.
- Snapshot fallback is only approved for relatively stable data:
  - standings
  - records overview / leaderboards
  - not full team player detail payloads
- Current backend direction is broader than early app-only fallback notes:
  - historical standings, past games, player detail, team players, and team stats may use stored backend snapshots
  - live relay / live scoreboard should remain live-first
- When adding fallback data, prefer generated assets over handwritten literals and keep the generation path under `scripts/`.
- If work clearly matches an existing local Claude skill under `.claude/skills/`, read that skill first and follow it.

## Design And UX Constraints
- Prioritize "open the app and see baseball immediately".
- Treat my-team personalization as a first-class requirement.
- Preserve the dark sports-app direction captured in `docs/FIGMA_PROMPT.md`.
- Default mobile frame assumptions to 390x844 unless a task explicitly targets another breakpoint or widget size.
- Preserve the information architecture defined in `docs/APP_SPEC.md`:
  - Onboarding
  - Home scoreboard
  - Game detail with score, relay, box score, lineup
  - Schedule
  - Standings
  - Settings
- Reuse the team color guidance and game status codes from `docs/PLANNING.md` and `docs/APP_SPEC.md`.
- Reuse these visual constants from `docs/FIGMA_PROMPT.md` unless the user changes them:
  - Backgrounds: `#0F0F0F`, `#1A1A1A`, `#252525`
  - Divider: `#333333`
  - Primary text: `#FFFFFF`
  - Secondary text: `#B0B0B0`
  - Disabled text: `#666666`
  - Live accent: `#FF4444`
  - Positive accent: `#00C853`
  - Action accent: `#2979FF`
  - Ball count yellow: `#FFD600`
- Use Pretendard for Korean-first UI copy and SF Pro-style numeric emphasis when drafting designs or frontend UI.
- Do not use emoji in app UI copy or labels. Prefer text, color, badges, or icons.

## Reusable Patterns
- Relay work should follow the login-based KBO live text flow documented in `.claude/skills/kbo-relay-integration/SKILL.md`.
- App-side direct KBO ASMX work should follow `.claude/skills/kbo-asmx-direct-integration/SKILL.md`.
- Home performance work should follow `.claude/skills/home-load-performance/SKILL.md`.
- Game detail tab UI work should follow `.claude/skills/game-detail-tab-polish/SKILL.md`.
- iOS device run and widget troubleshooting should follow `.claude/skills/ios-live-activity-widget/SKILL.md`.
- App startup / white-screen / noisy local runtime work should follow `.claude/skills/app-startup-runtime-triage/SKILL.md`.
- Connected iOS device run-action and Xcode destination triage should follow `.claude/skills/ios-device-run-action/SKILL.md`.
- Friend/tester distribution work should follow `.claude/skills/app-distribution/SKILL.md`.

## Figma Workflow Notes
- `docs/FIGMA_PROMPT.md` defines the current intended Figma page order and screen states.
- The intended page set includes:
  - User Flow
  - Onboarding
  - Home scoreboard states
  - Game detail tabs: score, relay, box score, lineup
  - Schedule
  - Standings
  - Settings
  - Widgets
- If Figma MCP is unavailable, blocked by rate limits, or blocked by account permissions, do not pretend the canvas work was completed.
- In that case, keep the prompt/spec documents up to date so the design handoff remains executable later.

## Backend And Data Constraints
- Backend APIs should follow the response envelope and endpoint contracts documented in `docs/APP_SPEC.md`.
- Backend currently targets Python `>=3.9` per `backend/pyproject.toml`, so backend code must remain Python 3.9 compatible unless the runtime policy is explicitly upgraded.
- Do not use Python 3.10+ only type syntax such as `int | None` or `str | None` in backend FastAPI/Pydantic code while Python 3.9 remains the minimum supported version. Use `Optional[...]` / `Union[...]` instead.
- If KBO login is required for relay or protected pages, keep credentials only in local secure storage such as `.env` or Keychain. Never write plaintext IDs/passwords into repository docs or committed files.
- Adaptive polling matters:
  - Scheduled games: 5 minutes
  - Live games: 30 to 60 seconds
  - Final games: stop polling after final persistence
- Local app mode may run without backend availability, so local/dev fallback behavior should be explicit rather than assumed.
- Respect crawler fragility and KBO site change risk; keep parsing logic modular.

## Distribution Notes
- For the fastest external sharing, prefer web first.
- For iPhone tester installs, prefer TestFlight.
- For Android tester installs, prefer Google Play internal testing after release signing is configured.
- Android release signing secrets live in `app/android/key.properties` and a local keystore; never commit them.
- iOS destinations depend heavily on active Xcode version and matching runtime/platform support.

## Repeatable Workflows
- Reuse `.claude/skills/ios-live-activity-widget/SKILL.md` when touching iOS WidgetKit / Live Activity / Dynamic Island logic.
- Reuse `.claude/skills/kbo-version-release/SKILL.md` when changing versions, tags, release notes, or in-app patch notes.
- Reuse `.claude/skills/mobile-preview-release/SKILL.md` only as a legacy checklist when preparing TestFlight readiness or Android signing docs; release tags now follow plain numeric `0.0.x` policy in `kbo-version-release`.

## Known Document Notes
- The active mobile direction for this repository is Flutter, not Expo or React Native.
- If future planning notes conflict with implementation docs, treat `CLAUDE.md`, `docs/WORKLOG.md`, and the latest code as the current direction.
- `docs/FIGMA_PROMPT.md` is more detailed than `CLAUDE.md` for visual decisions; prefer it for screen composition and styling details.
- `flutter devices` 와 `xcodebuild -showdestinations` 결과가 다를 수 있으니, 실기기 실행 이슈는 두 경로를 같이 본다.

## Claude Skill Notes
- Repetitive project-specific workflows that are now worth extracting live under `.claude/skills/`.
- If you update a Codex-facing workflow in `AGENTS.md`, update the corresponding Claude-side skill or context note in `.claude/skills/` or `CLAUDE.md` in the same task.
