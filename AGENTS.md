# KBO Fans Agent Guide

## Project Summary
- KBO Fans is a mobile app for KBO baseball fans on iOS and Android.
- The current agreed stack is Flutter + Dart for the app and Python FastAPI for the backend.
- Main data comes from KBO official sources via crawling and internal API calls, then is re-served through the backend.

## Source Of Truth
- Start with this file for repository-level working rules.
- Use `CLAUDE.md` for high-level project context.
- Use `README.md` for external-facing project summary, quick start, and local preview/run guidance.
- Use `CHANGELOG.md` for user-visible change history.
- Use `docs/APP_SPEC.md` for screen behavior, provider structure, API contracts, and status codes.
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
- Keep feature or task context as Markdown documents under `docs/` when the work is large enough to need durable context.
- Use Korean commit messages.
- Keep implementation aligned with Flutter, Riverpod, go_router, dio, FastAPI, AWS, and FCM unless the user explicitly changes direction.
- When changing UX flows, screen states, or navigation, update both the relevant spec doc and the work log in the same task when feasible.
- Treat design artifacts as first-class project context, not secondary references.

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
- Adaptive polling matters:
  - Scheduled games: 5 minutes
  - Live games: 30 to 60 seconds
  - Final games: stop polling after final persistence
- Respect crawler fragility and KBO site change risk; keep parsing logic modular.

## Known Document Notes
- The active mobile direction for this repository is Flutter, not Expo or React Native.
- If future planning notes conflict with implementation docs, treat `CLAUDE.md`, `docs/WORKLOG.md`, and the latest code as the current direction.
- `docs/FIGMA_PROMPT.md` is more detailed than `CLAUDE.md` for visual decisions; prefer it for screen composition and styling details.
