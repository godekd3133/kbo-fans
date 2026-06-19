# Home Reference Design QA - 2026-06-19

## Reference
- Target image: `docs/assets/mockups/integrated-visual-ui-2026-06-19.png`
- Target frame: 390x844 mobile home

## Implemented Alignment
- Header now follows the reference structure: `KBO` brand, centered `홈`, right-side notification/search actions.
- Home section order now follows the reference: my-team brief, today games, recent flow, standings preview, then secondary KBO/quick content.
- The standalone home visual rail was removed; generated visual texture remains as a low-opacity my-team brief background layer.
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
- `cd app && fvm flutter build web --release --dart-define=APP_ENV=release --dart-define=USE_BACKEND_API=true --dart-define=API_BASE_URL=http://127.0.0.1:8001/api`
- Screenshot: `.playwright-cli/page-2026-06-19T07-05-20-058Z.png`
- Side-by-side QA: `output/playwright/home-reference-vs-current-reference-api-release-final.png`

## Result
- blocked

## Residual Differences
- The browser web screenshot does not include the native iOS status bar shown in the reference image.
- Team logo artwork is sourced from current app/CDN assets, so several marks differ from the static reference image.
- The my-team brief background artwork is compositionally close but not pixel-identical to the reference card texture.
