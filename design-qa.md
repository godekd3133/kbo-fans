# Design QA

## Target
- Source visual truth: `docs/assets/mockups/kbo-onboarding-reference-2026-06-19.png`
- Viewport: 390x844
- Screen: Onboarding, my-team selection
- State: LG selected, web build seeded with `flutter.myTeam = "LG"`

## Evidence
- Implementation screenshot: `output/playwright/kbo-onboarding-reference/onboarding-selected-lg-final.png`
- Browser state/events: `output/playwright/kbo-onboarding-reference/onboarding-selected-lg-final-state.json`
- Generated reference image source: `/Users/kimminkyu/.codex/generated_images/019eddfe-3329-7cd2-a0ad-758335753293/ig_03a4c585892e1540016a34ff4026f08196814fc30523a7534a.png`

## Required Fidelity Surfaces
- Layout: title, subtitle, stadium hero, `MY TEAM` preview, two-column team cards, red CTA, and skip action follow the generated reference order.
- Image use: onboarding now uses a generated stadium hero asset cropped from the reference; team cards use image logos instead of text-only badges.
- Density: all ten team cards, CTA, and skip action are visible in the 390x844 capture.
- Visual language: dark sports surface, 8px card radius, red selected state, bordered cards, and compact Korean-first text match the KBO Fans reference direction.

## Findings
- No remaining P0/P1/P2 findings for the compared onboarding layout.
- P3: local web QA shows the development console floating button because `APP_ENV=local` wraps the app with `DevConsoleOverlay`; this is not production UI. Release web capture was blocked by pre-existing dirty `records_screen.dart` duplicate class state outside this onboarding change.
- P3: browser capture does not emulate iOS status-bar safe area. The implementation uses `SafeArea`; real iOS top positioning should include the system inset.

## Verification
- `cd app && fvm dart format lib/features/onboarding/onboarding_screen.dart lib/core/constants/visual_assets.dart`
- `cd app && fvm flutter analyze --no-pub lib/features/onboarding/onboarding_screen.dart lib/core/constants/visual_assets.dart`
- `cd app && fvm flutter build web --no-wasm-dry-run --dart-define=APP_ENV=local`
- Chrome CDP 390x844 capture with seeded LG selection: `output/playwright/kbo-onboarding-reference/onboarding-selected-lg-final-state.json`

## Result
- final result: passed
