# 2026-06-19 Onboarding Design QA

## Reference
- Generated reference: `docs/assets/mockups/kbo-onboarding-reference-2026-06-19.png`
- Runtime capture: `output/playwright/kbo-onboarding-reference/onboarding-selected-lg-final.png`

## Implementation Notes
- Replaced the explanatory chip/visual rail onboarding layout with a reference-style hierarchy: title, subtitle, stadium hero, selected team preview, two-column team grid, CTA, and skip.
- Added `assets/visuals/onboarding_stadium_hero.png`, cropped from the generated reference, and wired it through `VisualAssets.onboardingStadiumHero`.
- Team selection cards now use `KboTeamLogoImage` so the visible surface is image-logo based.

## Verification
- `cd app && fvm flutter analyze --no-pub lib/features/onboarding/onboarding_screen.dart lib/core/constants/visual_assets.dart`
- `cd app && fvm flutter build web --no-wasm-dry-run --dart-define=APP_ENV=local`
- Chrome CDP 390x844 capture with `flutter.myTeam = "LG"`

## Result
- Passed for onboarding layout fidelity.
- Known QA noise: local-only DevConsole floating button is visible in the web capture; production/release UI should not show it.
