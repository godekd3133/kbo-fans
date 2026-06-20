# 2026-06-19 Onboarding Design QA

## Reference
- Generated reference: `docs/assets/mockups/kbo-onboarding-reference-2026-06-19.png`
- Runtime capture: `output/playwright/kbo-onboarding-reference/onboarding-selected-lg-release.png`
- Full comparison: `output/playwright/kbo-onboarding-reference/onboarding-reference-vs-implementation-release.png`

## Implementation Notes
- Replaced the explanatory chip/visual rail onboarding layout with a reference-style hierarchy: title, subtitle, stadium hero, selected team preview, two-column team grid, CTA, and skip.
- Added `assets/visuals/onboarding_stadium_hero.png`, cropped from the generated reference, and wired it through `VisualAssets.onboardingStadiumHero`.
- Team selection cards now use reference-cropped raster logo assets so the visible card surface matches the generated mockup more closely than the generic text badge fallback.

## Verification
- `cd app && fvm flutter analyze --no-pub lib/features/onboarding/onboarding_screen.dart lib/core/constants/visual_assets.dart lib/core/config/app_config.dart lib/main.dart`
- `cd app && fvm flutter build web --no-wasm-dry-run --dart-define=APP_ENV=release`
- Chrome CDP 390x844 release capture with `flutter.myTeam = "LG"`

## Result
- Passed for onboarding layout fidelity.
- Remaining mismatch is P3 only: the web capture lacks the iOS status bar shown in the generated reference, and Flutter text rendering cannot be bit-identical to the generated bitmap.
