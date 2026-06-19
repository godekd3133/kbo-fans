# Home Reference Design QA - 2026-06-19

## Reference
- Target image: `docs/assets/mockups/integrated-visual-ui-2026-06-19.png`
- Target frame: 390x844 mobile home

## Implemented Alignment
- Header now follows the reference structure: `KBO` brand, centered `홈`, right-side notification/search actions.
- Home section order now follows the reference: my-team brief, today games, recent flow, standings preview, then secondary KBO/quick content.
- The standalone home visual rail was removed; generated visual texture remains as a low-opacity my-team brief background layer.
- The web QA frame now includes the reference status bar treatment, KBO logo asset, and reference team-logo assets for the visible home teams.
- Today games render as compact rows with stadium/time, team logos, score/status, team records, and my-team priority.
- Recent flow renders three compact team rows with up to five result bubbles.
- Standings preview renders from `/home.standingsPreview`, avoiding an extra current standings provider call on home.
- Bottom navigation uses the reference-style labels and simple icon presentation: `홈 / 경기 / 기록 / 뉴스 / 더보기`.
- Local web visual QA uses deterministic reference data from `scripts/kbo-reference-api.py` on `http://127.0.0.1:8001/api`.

## Verification
- `cd app && fvm flutter analyze --no-pub lib/core/config/app_config.dart lib/features/home/home_screen.dart lib/core/widgets/main_scaffold.dart lib/core/utils/game_status_label.dart lib/core/widgets/game_status_badge.dart`
- `cd app && fvm flutter analyze --no-pub lib/features/home/home_screen.dart lib/data/models/home_aggregate.dart lib/data/repositories/api_home_repository.dart test/features/home/home_screen_test.dart`
- `cd app && fvm flutter test --no-pub test/features/home/home_screen_test.dart`
- `backend/.venv/bin/ruff check backend/src/kbo_fans_backend/services/home.py backend/tests/test_home.py`
- `backend/.venv/bin/pytest -q backend/tests/test_home.py`
- `python3 -m py_compile scripts/kbo-reference-api.py`
- `git diff --check`
- `cd app && fvm flutter build web --release --no-wasm-dry-run --dart-define=APP_ENV=release --dart-define=USE_BACKEND_API=true --dart-define=API_BASE_URL=http://127.0.0.1:8001/api`
- Screenshot: `.playwright-cli/page-2026-06-19T07-38-07-394Z.png`
- Side-by-side QA: `output/playwright/home-reference-vs-current-reference-api-release-final.png`
- Grid QA: `output/playwright/ref-grid-final.png`, `output/playwright/impl-grid-final.png`

## Result
- passed

## Residual Differences
- Native iOS capture should still be used before release-signoff if exact device status bar rendering is required.
- Flutter font antialiasing and raster compression are not expected to be pixel-identical to the static mockup.
