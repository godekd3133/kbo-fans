# Records Tab No-Clip Design QA - 2026-06-20

## Reference

- Source screenshot: `/tmp/codex-remote-attachments/019ee41b-3556-77d0-925f-c7bd14097024/3370B30C-AD41-4F77-8023-780300A27107/1-사진-1.jpg`
- Regenerated reference: `docs/design_refs/2026-06-20-records-tab-no-clip-reference.png`
- Final API-backed capture: `output/playwright/kbo-records-premium/records-390x844-no-clip-data-final.png`
- Target frame: 390x844 records tab first viewport

## Fix Criteria

- Stadium visual remains a dark background texture, not a foreground overlay.
- Spotlight cards show metric label, rank/player, team/gap, and value without vertical clipping.
- The first three spotlight cards fit the viewport cleanly at 390px width.
- Leaderboard metric tabs show `AVG`, `HR`, `OPS`, `wRC+`, and `ERA` without right-edge clipping.
- Bottom navigation does not cover the visible first two leaderboard rows.

## Implementation Check

- `app/lib/features/records/records_screen.dart`
  - Spotlight rail now calculates card width from the available viewport width.
  - Spotlight rail height increased from 104 to 116.
  - Spotlight value text uses a fixed-height `FittedBox`.
  - Leaderboard header gained a compact `전체 보기` CTA.
  - Leaderboard tabs now divide the available card width by metric count instead of using fixed 78px tabs.

## Validation

- `cd app && fvm dart format lib/features/records/records_screen.dart`
- `cd app && fvm flutter analyze --no-pub lib/features/records/records_screen.dart`
- `cd app && fvm flutter analyze --no-pub lib/features/records/records_screen.dart lib/data/repositories/kbo_direct_repository.dart lib/features/news/news_screen.dart lib/features/game_detail/game_detail_screen.dart`
- `cd app && fvm flutter build web --release --no-wasm-dry-run --pwa-strategy=none --dart-define=USE_BACKEND_API=true --dart-define=API_BASE_URL=http://127.0.0.1:8001/api --dart-define=APP_ENV=local --dart-define=SHOW_DEV_CONSOLE=false`
- Playwright 390x844 API capture on `http://127.0.0.1:4192`: `output/playwright/kbo-records-premium/records-390x844-no-clip-data-final.png`
- Playwright console errors: 0
- Backend records overview smoke: `최원준 오스틴 1.067`

## Result

final result: passed
