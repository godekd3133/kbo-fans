# Historical Design QA

## Target

- Source visual truth: `docs/assets/mockups/kbo-onboarding-reference-2026-06-19.png`
- Viewport: 390x844
- Screen: Onboarding, my-team selection
- State: LG selected, web build seeded with `flutter.myTeam = "LG"`

## Evidence

- Implementation screenshot: `output/playwright/kbo-onboarding-reference/onboarding-selected-lg-release.png`
- Browser state/events: `output/playwright/kbo-onboarding-reference/onboarding-selected-lg-release-state.json`
- Full-view comparison: `output/playwright/kbo-onboarding-reference/onboarding-reference-vs-implementation-release.png`
- Focused comparison crops:
  - `output/playwright/kbo-onboarding-reference/onboarding-compare-top_hero-release-small.png`
  - `output/playwright/kbo-onboarding-reference/onboarding-compare-team_grid-release-small.png`
  - `output/playwright/kbo-onboarding-reference/onboarding-compare-cta-release-small.png`
- Generated reference image source: `/Users/kimminkyu/.codex/generated_images/019eddfe-3329-7cd2-a0ad-758335753293/ig_03a4c585892e1540016a34ff4026f08196814fc30523a7534a.png`

## Historical Required Fidelity Surfaces

- Layout: title, subtitle, stadium hero, `MY TEAM` preview, two-column team cards, red CTA, and skip action follow the generated reference order.
- Image use: onboarding uses a generated stadium hero asset cropped from the reference; team cards use reference-cropped raster logo assets instead of text-only badges.
- Density: all ten team cards, CTA, and skip action are visible in the 390x844 capture.
- Visual language: dark sports surface, 8px card radius, red selected state, bordered cards, and compact Korean-first text match the KBO Fans reference direction.

## Historical Findings

- No remaining P0/P1/P2 findings for the compared onboarding layout.
- P3: browser release capture does not render the iOS status bar that appears in the generated reference. The implementation uses `SafeArea`, so real iOS top positioning should include the system inset.
- P3: Flutter font anti-aliasing and native browser rendering differ slightly from the generated bitmap reference, but the card hierarchy, spacing, CTA placement, selected state, and team-grid structure align.

## Historical Verification

- `cd app && fvm dart format lib/features/onboarding/onboarding_screen.dart lib/core/constants/visual_assets.dart`
- `cd app && fvm flutter analyze --no-pub lib/features/onboarding/onboarding_screen.dart lib/core/constants/visual_assets.dart lib/core/config/app_config.dart lib/main.dart`
- `cd app && fvm flutter build web --no-wasm-dry-run --dart-define=APP_ENV=release`
- Chrome CDP 390x844 release capture with seeded LG selection: `output/playwright/kbo-onboarding-reference/onboarding-selected-lg-release-state.json`

Historical result: passed

---

# KBO Fans UI/UX Design QA

## Source Visual Truth

- Selected source: `artifacts/uiux-redesign-2026-09-10/selected-home-with-team-logos.png`
- Normalized source: `artifacts/uiux-redesign-2026-09-10/source-home-normalized-390.png`
- Source pixels: 853×1844; normalized comparison pixels: 390×844
- Target CSS viewport: 390×844; source density was normalized to 1× before comparison

## Implementation Evidence

- Implementation: Flutter release web build served at `http://127.0.0.1:7357/#/home`
- Browser: Codex In-app Browser with CDP mobile metrics override, `innerWidth=390`, `innerHeight=844`, `devicePixelRatio=1`, `visualViewport.scale=1`
- Browser-rendered implementation capture: emitted and inspected inline from `Page.captureScreenshot` during this QA pass. The CUA download API did not expose a persistent filesystem path, so no non-equivalent placeholder capture is referenced as evidence.
- Additional browser-rendered states inspected at the same viewport: `/records`, `/schedule`, `/news`, `/settings`, `/game/20260908WOLG0?tab=score`, score/relay/boxscore/lineup tabs, and `/onboarding?mode=edit`.

## State

The source visual shows a LIVE LG–Doosan matchup. The current KBO date in the release browser is 2026-09-10, where the upstream response has no LG game and the app correctly shows the next scheduled LG–Samsung game plus today and yesterday result rows. The LIVE source state is covered by the app's widget fixture; browser evidence uses the current no-game state because the UI must not invent a live result.

## Full-View Comparison

- Header hierarchy is preserved: KBO Fans identity, KST date, notification/search actions.
- Home notification action exposes the stored unread count as a compact red badge and includes the count in its accessible tooltip; the badge is absent when there are no unread entries and follows inbox writes/read receipts while the home screen remains mounted.
- API diagnostics exposes a single in-flight refresh action with a visible progress indicator instead of allowing overlapping diagnostic requests.
- Records refresh actions use the same single in-flight behavior for overview and team records, keeping header, pull-to-refresh, and retry paths from overlapping.
- Standings refresh actions expose the same single in-flight behavior and visible progress state across header, pull-to-refresh, and retry/empty paths.
- Schedule monthly and matchup refresh paths share one in-flight guard so retry and pull-to-refresh do not overlap their provider fan-out.
- Briefing refresh paths share one in-flight guard and visible progress state across header, pull-to-refresh, and error retry.
- Notification inbox list/settings reloads coalesce concurrent refresh and retry calls so the visible timeline and playbook remain from the latest completed request.
- Player detail refresh and retry share one in-flight request, preventing duplicate player provider loads.
- API diagnostic cards expose status, detail, elapsed time, and note as one coherent accessibility summary.
- Home hierarchy remains score-first: selected-team focus, today/yesterday game rows with actual logos, then team brief and records.
- The release browser visibly renders transparent KBO team marks instead of the selected source's abstract letter badges. LG, Doosan, Kiwoom, Hanwha, Samsung, KT, NC, KIA, SSG, and Lotte paths are provided by `KboTeamLogoImage`.
- Bottom navigation preserves five destinations and uses blue action accent for selection.
- Home standings preview uses team identity color for the highlighted my-team row; LIVE red remains reserved for live game status.
- Home recent-result bubbles use positive/negative/draw semantic colors instead of reusing LIVE red for wins.
- Game detail highlight playback mode uses action blue for its ordinary selection state.
- Release notes current-version and bullet markers use action blue rather than LIVE red.
- Standalone leaderboard group selection uses the same action-blue control language as the records hub.
- Startup release-notes prompt uses the same action-blue information state.
- Data loading indicators use action blue rather than LIVE red across the audited screens.
- Pull-to-refresh indicators use action blue rather than LIVE red across the audited screens.
- Briefing refresh uses the same action-blue loading state.
- Records and standings normal data areas now use flat surfaces; background artwork remains only in state-specific retry/empty surfaces.

## Focused Region Comparison

- Home focus region: source's LIVE card was compared with the implemented `_LiveMyTeamGameCard` fixture structure. Both use team identities on the sides, central score/inning, status, and a single next action. The implementation uses the real transparent logo assets.
- Home compact list region: current browser capture was inspected for logo scale, team-name wrapping, score availability, status badges, row dividers, and chevrons. The current no-game state shows `– : –` for scheduled games rather than a synthesized score.
- Persistent navigation region: mobile and 700px+ rail semantics were checked through the browser accessibility tree and Flutter tests; all five mobile tap targets remain at least 48px high.

## Required Fidelity Surfaces

### Fonts and typography

Jua remains the app display family with NanumSquareRound and Pretendard fallback. The selected display hierarchy is implemented with a compact 19–26px title range, 12–14px metadata, and larger score text. The 320px/240% test path reflows the home header instead of clipping brand/date/actions.

### Spacing and layout rhythm

Home uses 16px page gutters, 8px compact surfaces, 12px hero surfaces, 5–24px section gaps, and fixed 44–48px pressable minimums. The compact home list keeps the original 48px baseline row height so lower sections and the bottom navigation do not hide the standings action.

### Colors and visual tokens

The implementation maps the selected direction to the existing accessible palette: ink background, charcoal surface, white primary text, readable secondary text, blue actions, red LIVE state, and team-color rails. LIVE red is not used for ordinary selection; records/standings selection uses action blue.

### Image quality and asset fidelity

Team identity is rendered with the repository's transparent PNG assets through `KboTeamLogoImage`, with network fallback only when an asset fails. No CSS/HTML logo drawing, emoji, or letter badge is used in the implementation. Normal records/standings views no longer place a decorative stadium bitmap behind dense data.

### Copy and content

The static UI copy stays Korean-first and action-oriented: `내 경기 진행 중`, `오늘 경기`, `문자중계 보기`, `기록실`, `다시 시도`, and `경기 상세`. Dynamic score/status copy continues to come from the existing game state contract; unavailable values remain explicit.

### Icons and interactions

Material icons are used for navigation, search, notifications, calendar, refresh, chevrons, and baseball context. Browser accessibility inspection confirmed notification/search actions, tabs, team rows, schedule controls, and mobile navigation labels. Core tab, route, selection, loading, error, empty, and retry interactions remain functional.

## Findings

No actionable P0/P1/P2 visual findings remain for the implemented scope.

The source and browser state differ intentionally because the source is a LIVE fixture while 2026-09-10 has no current LG game. Treating that as a design defect would require inventing live data, so it is classified as an evidence-state difference rather than an implementation mismatch.

## Comparison History

1. Initial pass found that the old normal data surfaces still used decorative stadium artwork and the new header needed a stronger brand signal. Removed normal records/standings background artwork and added the KBO Fans wordmark alongside the real brand mark.
2. The LIVE home card initially repeated an unavailable dash in both team rows and the central score. Changed the team rows to logo/name-only in the hero and kept the score pair in the central score group; the home unknown-score regression then passed.
3. The header initially overflowed at 320px and 240% text. Added a compact responsive header that preserves the logo/date/actions without clipping; large-text home regressions passed.
4. Final browser pass inspected the current 390px home, records, schedule, briefing, settings, game score, relay, boxscore, lineup, and onboarding states. No P0/P1/P2 issue remained.

## Verification

- `fvm flutter analyze`: `No issues found`
- Flutter full suite: `620` tests passed in the latest run. The scheduled quick-item score-integrity regressions, home unread badge, home header action semantics, live inbox-sync, diagnostics refresh, records refresh, inbox-loader coalescing, player-detail refresh, diagnostic-semantics, update-prompt semantics, patch-note semantics, single-control appearance semantics, boxscore player-row action semantics, labeled-pressable boundary, schedule-header action, home-standings-row action, onboarding selected-state, and page-header boundary regressions are included in this count.
- Latest focused regressions: home `53 passed`, notification inbox `11 passed`, player detail `5 passed`, API diagnostics `3 passed`, patch notes `3 passed`, records refresh `2 passed`, theme `13 passed`; earlier standings, schedule, game detail, and onboarding checks remain covered by the full suite.
- Latest scheduled-score regression: Flutter news suite passed `22` tests, backend producer/consumer focus passed `90` tests, and the full backend suite passed `719` tests.
- Release web build: successful with `--no-wasm-dry-run`; known Wasm incompatibility was not used as a JavaScript build failure.
- Browser console/UI state: no browser console error was observed during the inspected routes; accessibility trees exposed the expected controls.
- Update prompt accessibility: header and change-point groups are explicit semantics containers, and the focused prompt suite passed `9` tests after settling the asynchronous dialog transition.
- Settings accessibility: each appearance option is exposed once as `시스템 모드`, `라이트 모드`, or `다크 모드`; nested button semantics were removed and the focused settings suite passed `22` tests.
- Boxscore accessibility: a matched player row exposes its player-record tap action on the same summary node; the settings plus boxscore focused run passed `43` tests.
- Game-detail accessibility: the current Web AX tree exposes exactly one `뒤로` button and player rows as single buttons with `선수 기록 보기`; the focused navigation suite passed `30` tests.
- Shared pressable accessibility: labeled `AppPressable` nodes no longer merge parent header copy into the action label; the focused `AppPressable` suite passed `7` tests.
- Schedule accessibility: the latest Web AX tree exposes `이전 달`, `다음 달`, and `오늘로 이동` as separate single buttons; the schedule suite passed `26` tests.
- Home accessibility: the latest Web AX tree exposes each standings preview row as one `팀 순위 전체 보기` button; the home and onboarding focused run passed `65` tests.
- Records-team accessibility: the latest Web AX tree exposes one `뒤로` button in the team-detail route; the focused rollover suite passed `3` tests.
- Onboarding accessibility: edit-mode back navigation keeps one named action node; the focused onboarding suite passed `11` tests.
- Page-header accessibility: the latest Web AX tree keeps `뒤로`, title, and subtitle as separate nodes inside an explicit header container; the focused header test passed.
- Home header accessibility: the latest Web AX tree exposes `알림함` and `기록 검색` as labeled buttons with their actions, including unread-count label behavior.
- Game-detail mode accessibility: video `스크롤` and `플레이어 조작` chips now expose selected state through the shared pressable semantics.
- Records category color: the `마운드 체크` panel uses action blue while LIVE red remains reserved for live/event meaning; player-image surfaces focused tests passed `11` tests.
- Home header hit target: notification and search actions are declared at 44px and resolve to Material `48×48` controls in the focused home interaction test.
- Season selector hit target: standings and records-team selector surfaces are explicitly at least `44px` high; standings plus records rollover focused tests passed `13` tests.
- Settings section-row accessibility: tappable rows no longer wrap `AppPressable` in a second button semantics node; the focused settings suite passed `22` tests.
- Scheduled-score integrity: backend `/api/home` quick items use `vs` and `/api/scoreboard/home` keeps scheduled team scores `null`; the browser AX tree shows `LG vs 삼성` and no inferred `0 : 0`.

## Page-by-Page Design Handoff

- Page intent and state targets: `docs/design_refs/2026-09-10-page-by-page-screens.md`
- Current 390×844 route/state manifest: `artifacts/uiux-redesign-2026-09-10/page-captures/README.md`
- The current pass also inspected the secondary routes `/notifications`, `/records/leaderboard/AVG`, `/records/player/53123?season=2026`, `/diagnostics`, and `/release-notes` after the common-header update.

## Follow-up Polish

- Capture a real LIVE upstream game at 390×844 when one is available to complement the deterministic fixture proof.
- Verify VoiceOver/TalkBack on physical devices separately from Flutter widget semantics.
- Do not treat this design QA as proof of backend, push, Live Activity, TestFlight, Play Console, or external installability.

final result: passed
