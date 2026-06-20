# News Tab Design QA - 2026-06-19

## Reference

- Generated reference: `docs/design_refs/2026-06-19-news-tab-reference.png`
- Diverse generated reference: `docs/design_refs/2026-06-19-news-tab-diverse-reference.png`
- Redraft reference after AI-like card feedback: `docs/design_refs/2026-06-20-news-tab-reference-redraft.png`
- theScore: scores, news, stats, videos, alerts, and favorite-feed style sports utility
- MLB App: favorite-team live game entry, personalized news filters, player alerts, highlights
- Reuters App: `Today` hub, personalized `My News`, related content, utility-first news reading
- Sofascore News: category tabs and stats-backed sports stories
- MyKBO Stats: KBO schedule, standings, starting pitchers, results, stats, and live game day coverage

## Direction

- Keep the tab as a KBO briefing surface, not an external article crawler.
- Use verified `HomeAggregate` data only: `kboBrief.items`, `quickItems`, `standingsPreview`, and `myTeamBrief`.
- Put a compact editorial lead above filters so the user sees the top three items before browsing categories.
- Use a reference-like segmented filter row instead of pill overload.
- Use article-like rows for the main list, not repeated large template cards.
- Make rows visually distinct with `imageUrl` first and bundled reference team logos second.
- Never derive arbitrary two-syllable team-name abbreviations from Korean words such as `삼라`; if a team visual is needed, resolve `teamId` or team name through the shared KBO team logo widget.
- Keep cards dense, dark, and product-like: 8px radius, no emoji, no oversized hero, no decorative gradient.

## Implementation Check

- `app/lib/features/news/news_screen.dart`
  - Keeps editorial lead and ranked read order.
  - Replaced `뉴스 믹스` rail and 2x2 signal grid with a single segmented filter row.
  - Expanded card source data to include quick items, standings preview rows, and my-team recent game summaries.
  - Changed main cards into article-like rows with left visual, compact metadata, title, one-line summary, and CTA.
  - Added `teamId` propagation into news rows so bundled reference team logos replace fallback text marks.
  - Kept source labels internal: scoreboard, standings, records, personalized, recommendation.
- `app/test/features/news/news_screen_test.dart`
  - Covers KBO brief item rendering and quick item expansion.
  - Covers my-team recent game and standings-preview derived cards.
  - Keeps empty-state behavior covered.

## Validation

- `cd app && fvm flutter analyze --no-pub lib/features/news/news_screen.dart test/features/news/news_screen_test.dart`
- `cd app && fvm flutter test --no-pub test/features/news/news_screen_test.dart -r expanded`
- `cd app && fvm dart format lib/features/news/news_screen.dart test/features/news/news_screen_test.dart`
- `python3 -m py_compile scripts/kbo-reference-api.py`
- `cd app && fvm flutter build web --release --no-wasm-dry-run --dart-define=USE_BACKEND_API=true --dart-define=API_BASE_URL=http://127.0.0.1:8014/api --dart-define=SHOW_DEV_CONSOLE=false --output /tmp/kbo-news-web-clean`
- Browser 390x844 capture:
  - `output/playwright/news-redraft/news-390x844.png`
  - `/tmp/kbo-news-tab-qa/news-mobile-initial.png`
  - `/tmp/kbo-news-tab-qa/news-mobile-records-filter.png`
  - `/tmp/kbo-news-tab-qa/news-diverse-clean-initial.png`
  - `/tmp/kbo-news-tab-qa/news-diverse-clean-rank-filter.png`
  - `/tmp/kbo-news-tab-qa/news-diverse-clean-player-mix-filter.png`
  - `/tmp/kbo-news-tab-qa/news-diverse-clean-records-scroll.png`

## Visual Notes

- First viewport shows date, title, refresh, editorial lead, segmented filters, section header, and article rows without text overlap.
- `기록` filter changes selected underline and narrows the section header to `기록 뉴스`.
- `순위` state narrows the section header to `순위 뉴스` and shows standings-derived rows.
- Player/record stories stay in the same dense reading lane through the `기록` filter.
- Clean release capture uses `SHOW_DEV_CONSOLE=false`, so no local Dev Console affordance overlaps the cards.
- QA network trace should return `/api/home` and visible KBO player image requests as HTTP 200; if an image fails, the row must show a team logo or single neutral fallback, not a generated Korean abbreviation.
- Bottom navigation remains fixed and the list scrolls underneath as expected.
