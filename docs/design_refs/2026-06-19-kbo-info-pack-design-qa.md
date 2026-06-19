# KBO Info Pack Design QA - 2026-06-19

## Reference
- Generated reference: `docs/assets/mockups/kbo-info-pack-reference-2026-06-19.png`
- Viewport: 390x844
- Target state: Home section where standings lead into `인사이트` and `지금 보면 좋은 정보`

## Implementation Evidence
- Final screenshot: `output/playwright/kbo-info-pack-reference/home-pack-final3-06.png`
- API trace: `output/playwright/kbo-info-pack-reference/home-pack-final3-events.json`
- Reference API: `http://127.0.0.1:8011/api/home?date=2026-06-19&myTeam=LG`

## Result
- The home info flow now follows the reference order: standings preview, insight pack, then two-column quick info.
- The insight pack shows eight signals as card-news content: topic cards, LIVE score strip, four compact cards, and schedule CTA.
- No P0/P1/P2 visual blockers remain for this target section.
- P3 difference remains: generated decorative team/photo imagery is represented with the app's bundled logo/icon assets rather than a literal bitmap clone.

## Verification
- `cd app && fvm flutter analyze --no-pub lib/features/home/home_screen.dart lib/data/models/home_aggregate.dart`
- `cd app && fvm flutter build web --no-wasm-dry-run --dart-define=USE_BACKEND_API=true --dart-define=API_BASE_URL=http://127.0.0.1:8011/api`
- `python3 -m py_compile scripts/kbo-reference-api.py backend/src/kbo_fans_backend/services/home.py`
