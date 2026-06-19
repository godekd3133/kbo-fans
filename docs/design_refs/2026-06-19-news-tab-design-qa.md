# News Tab Design QA - 2026-06-19

## Reference

- Generated reference: `docs/design_refs/2026-06-19-news-tab-reference.png`
- Diverse generated reference: `docs/design_refs/2026-06-19-news-tab-diverse-reference.png`
- theScore: scores, news, stats, videos, alerts, and favorite-feed style sports utility
- MLB App: favorite-team live game entry, personalized news filters, player alerts, highlights
- Reuters App: `Today` hub, personalized `My News`, related content, utility-first news reading
- Sofascore News: category tabs and stats-backed sports stories
- MyKBO Stats: KBO schedule, standings, starting pitchers, results, stats, and live game day coverage

## Direction

- Keep the tab as a KBO briefing surface, not an external article crawler.
- Use verified `HomeAggregate` data only: `kboBrief.items`, `quickItems`, `standingsPreview`, and `myTeamBrief`.
- Put a compact editorial lead above filters so the user sees the top three items before browsing categories.
- Add a `뉴스 믹스` rail so live, player, standings, record, schedule, and my-team story kinds are visible before the card list.
- Use a 2x2 signal grid for quick category scanning: game flow, standings, records, my team.
- Make cards visually distinct when data allows it by using `imageUrl` or `fallbackLabel` thumbnail marks.
- Keep cards dense, dark, and product-like: 8px radius, no emoji, no oversized hero, no decorative gradient.

## Implementation Check

- `app/lib/features/news/news_screen.dart`
  - Added editorial lead and ranked read order.
  - Added `뉴스 믹스` rail with story-kind counts and filter shortcuts.
  - Added category signal grid with filter shortcuts.
  - Expanded card source data to include quick items, standings preview rows, and my-team recent game summaries.
  - Added optional visual marks from `imageUrl` / `fallbackLabel`.
  - Kept source labels internal: scoreboard, standings, records, personalized, recommendation.
- `app/test/features/news/news_screen_test.dart`
  - Covers KBO brief item rendering and quick item expansion.
  - Covers my-team recent game and standings-preview derived cards.
  - Keeps empty-state behavior covered.

## Validation

- `cd app && fvm flutter analyze --no-pub lib/features/news/news_screen.dart test/features/news/news_screen_test.dart`
- `cd app && fvm flutter test --no-pub test/features/news/news_screen_test.dart -r expanded`
- `cd app && fvm flutter build web --no-wasm-dry-run --dart-define=USE_BACKEND_API=true --dart-define=API_BASE_URL=http://127.0.0.1:8012/api`
- Browser 390x844 capture:
  - `/tmp/kbo-news-tab-qa/news-mobile-initial.png`
  - `/tmp/kbo-news-tab-qa/news-mobile-records-filter.png`
  - pending diverse follow-up capture

## Visual Notes

- First viewport shows date, title, refresh, editorial lead, filter chips, signal grid, and the first card without text overlap.
- `기록` signal tile changes selected state and narrows the section header to `기록 브리프`.
- Bottom navigation remains fixed and the list scrolls underneath as expected.
