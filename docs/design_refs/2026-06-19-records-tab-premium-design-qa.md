# Records Tab Premium Design QA - 2026-06-19

## Reference

- Generated reference: `docs/design_refs/2026-06-19-records-tab-premium-reference.png`
- Target frame: mobile records tab, 390x844 logical viewport
- Direction: darker premium sports data room with more processed league leader information before team search

## Direction

- Keep the records tab as a data surface, not a decorative landing page.
- Put the processed read order first: headline leader, active metric count, TOP5 player coverage, source confidence.
- Use AVG/HR/OPS/wRC+/ERA as the first scan rail so users can compare league leaders before opening a full leaderboard.
- Replace stacked preview cards with one tabbed TOP3 leaderboard table to increase information density in the first viewport.
- Use official player image and team logo where available, with text fallback only when images fail.
- Preserve the existing data contract: `RecordsOverview` remains the single source for league briefing, spotlight cards, and preview rows.

## Implementation Check

- `app/lib/features/records/records_screen.dart`
  - Added the generated-reference-style stadium backdrop behind the records chooser.
  - Enlarged the `기록실` header and tightened subtitle/season spacing.
  - Reworked `오늘 읽을 기록` into a premium briefing card with headline player image, metric chips, active metric count, TOP5 coverage, source badge, and 2-3 interpreted brief lines.
  - Reworked metric spotlight cards with rank badge, leader/team/value, and 2위 gap text.
  - Replaced the old metric preview stack with tabbed TOP3 leaderboard rows and a metric-specific full leaderboard CTA.
  - Kept team search and team records entry under the league briefing flow.

## Validation

- `cd app && fvm flutter analyze --no-pub lib/features/records/records_screen.dart`
- `cd app && fvm flutter analyze --no-pub lib/features/records/records_screen.dart test/data/bootstrap_repository_test.dart`
- `cd app && fvm flutter test --no-pub test/data/bootstrap_repository_test.dart test/data/models/records_overview_test.dart -r expanded`
- `cd app && fvm flutter build web --release --no-wasm-dry-run --dart-define=USE_BACKEND_API=false --dart-define=APP_ENV=local`
- Browser 390x844 capture: `output/playwright/kbo-records-premium/records-390x844-final-table.png`

## Visual Notes

- First viewport should show the `기록실` title, season selector, premium briefing card, and the beginning of the metric rail.
- The generated reference uses a bitmap stadium top texture; implementation uses a lightweight Flutter-painted stadium backdrop to avoid adding another runtime image dependency.
- Text must stay inside cards at 390px width; long player/team names are single-line ellipsized in rank rows and metric cards.
- Current-season local/direct records data is backed by `app/assets/bootstrap/records_overview.json` generated from `backend/data/snapshots/records_overview/2026.json`; freshness guard remains intact.
