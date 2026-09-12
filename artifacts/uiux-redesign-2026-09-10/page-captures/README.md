# Page Capture Manifest

## Capture Context

- Date: 2026-09-11 KST
- Latest runtime revalidation: 2026-09-12 KST, fresh local API/Web release bundle
- Viewport: Chrome responsive viewport 390×844
- Build: Flutter web release, `APP_ENV=local`, `USE_BACKEND_API=true`, `API_BASE_URL=http://127.0.0.1:8000/api`, `SHOW_DEV_CONSOLE=false`
- Backend: local FastAPI on `127.0.0.1:8000`, health response 200
- Evidence rule: the screenshots were inspected inline from the current Chrome tab after the route settled. This manifest records the accepted route/state evidence; it does not claim device, push, Live Activity, or release validation.

## Accepted Screens

| ID | Route | Accepted state | Result |
|---:|---|---|---|
| 01 | `#/home` | current day, scheduled games and yesterday results | pass |
| 02 | `#/schedule` | September calendar, my-team highlight, ticket row | pass |
| 03 | `#/standings` | 2026 standings with selected team rail | pass |
| 04 | `#/records` | team records hub, season leaders, leaderboard entry | pass |
| 05 | `#/news` | data briefing with three insight cards and feed | pass |
| 06 | `#/settings` | my team, appearance, push preset | pass |
| 07 | `#/onboarding?mode=edit` | Samsung selected, team grid and completion CTA | pass |
| 08 | `#/notifications` | empty inbox and notification playbook | pass |
| 09 | `#/game/20260910WOOB0?tab=score` | finished game scorebug and inning table | pass |
| 10 | `#/game/20260910WOOB0?tab=relay` | finished game relay summary and filters | pass |
| 11 | `#/game/20260910WOOB0?tab=boxscore` | team toggle and live/official data transition | pass after settle |
| 12 | `#/game/20260910WOOB0?tab=lineup` | team lineup and starter rows | pass after settle |
| 13 | `#/records/leaderboard/AVG` | hitter AVG leaderboard with blue metric selection | pass |
| 14 | `#/records/player/53123?season=2026` | player identity and season metric grid | pass |
| 15 | `#/diagnostics` | health, scoreboard, schedule, push state cards | pass |
| 16 | `#/release-notes` | current version banner and user-facing release notes | pass |

## Notes

- The first home and game-detail observations were loading frames; they were rejected and recaptured after the API-backed state settled.
- The first boxscore/lineup observations were tab transition frames; they were rejected and recaptured after the TabBarView settled. The stable state was also covered by the existing game-detail navigation tests.
- API latency values shown in the diagnostics screen are local upstream timing observations, not a release SLO claim.
- Latest polish pass: settings appearance selection uses action blue, notification inbox uses the common page header and blue filters, and the normal score-tab line score uses a flat data surface without background artwork.
- Latest detail pass: the lineup tab presents the two-team starting lineups before optional matchup/trend comparison content, while wide layouts remain side by side and narrow layouts reflow vertically.
- Latest relay pass: inning and moment filters use action blue for selection, while event cards retain their scoring/substitution/end-state meaning colors.
- Latest boxscore pass: live-context team summaries show a visible `LIVE` status pill before the metric tiles; official and unavailable states keep their existing labels.
- Latest settings pass: push preset selection uses theme action blue while the my-team target strip retains team identity color.
- Latest briefing pass: purpose filters use theme action blue while briefing card accents retain game, standings, and records meaning colors.
- Latest schedule pass: view mode, team filters, and selected date use action blue while game-day outlines remain red; the stable browser capture shows the two meanings separately.
- Latest records pass: player-list tabs, filters, sorting, leaderboard groups, and metric selection use action blue while team and metric data accents remain semantic.
- Latest standalone leaderboard pass: hitter/pitcher group selection matches the records hub action-blue language.
- Latest home pass: the my-team standings preview uses team identity color instead of LIVE red; live game cards retain the red LIVE state.
- Latest home result pass: recent `승`/`패`/`무` bubbles and streak labels use positive/negative/action semantic colors.
- Latest game-detail pass: highlight playback mode chips use action blue while live and event status colors remain semantic.
- Latest release-notes pass: installed-version badge and note bullets use action blue while diagnostic/live red remains semantic.
- Latest release prompt pass: startup update icon and bullets use the same action-blue information state.
- Latest loading-state pass: data spinners use action blue while live/error/event red remains semantic.
- Latest refresh-state pass: pull-to-refresh indicators use action blue while LIVE red remains reserved for game state.
- Latest briefing refresh pass: the briefing route uses the same action-blue refresh indicator.
- Latest accessibility pass: the update prompt exposes explicit header and change-point summaries, and the Patch Notes cards expose one coherent summary without duplicate child semantics; focused tests passed `9` and `3` respectively.
- Latest interaction accessibility pass: settings appearance options expose one button each, and matched boxscore player rows expose their player-record tap action on the summary node; the focused settings plus boxscore run passed `43` tests.
- Latest game-detail accessibility pass: the current Web AX tree exposes one `뒤로` button and single-action player rows with `선수 기록 보기`; the focused navigation suite passed `30` tests.
- Latest shared-control accessibility pass: labeled `AppPressable` headers keep `뒤로` separate from page title/subtitle text; focused AppPressable tests passed `7` tests and the notification AX tree shows separate back and header nodes.
- Latest schedule accessibility pass: the current Web AX tree exposes `이전 달`, `다음 달`, and `오늘로 이동` as single buttons separate from the month title; the schedule suite passed `26` tests.
- Latest home/onboarding accessibility pass: home standings preview rows expose single `팀 순위 전체 보기` actions, and team cards keep selected semantics through AppPressable; focused home plus onboarding tests passed `65` tests.
- Latest records-team accessibility pass: the team-detail AX tree exposes one `뒤로` button separate from the team title and filters; focused rollover tests passed `3` tests.
- Latest onboarding accessibility pass: edit-mode back navigation exposes one named `뒤로` action; focused onboarding tests passed `11` tests.
- Latest page-header accessibility pass: the notification AX tree exposes a description-free header container with separate `뒤로`, title, and subtitle nodes; the focused header test passed.
- Latest home-header accessibility pass: the Home AX tree exposes labeled `알림함` and `기록 검색` buttons directly; unread-count label behavior remains covered by the home focused tests.
- Latest game-detail mode pass: `스크롤` and `플레이어 조작` video chips keep action-blue selection and expose selected state through AppPressable.
- Latest records category-color pass: the `마운드 체크` panel uses action blue instead of LIVE red; player-image surfaces focused tests passed `11` tests.
- Latest home hit-target pass: header notification/search controls meet the 44px minimum and render as 48px Material targets while retaining direct labels.
- Latest season-selector pass: standings and records-team season surfaces meet the 44px minimum; combined focused geometry checks passed `13` tests.
- Latest settings interaction pass: tappable section rows expose one `AppPressable` action without an outer duplicate button semantics wrapper; the focused settings suite passed `22` tests.
- Latest scheduled-score integrity pass: backend `/home` quick items and `/scoreboard/home` no longer promote scheduled `0 : 0` placeholders; Flutter news checks passed `22` tests, backend producer/consumer checks passed `90` tests, and the fresh Web AX tree shows `LG vs 삼성`.
