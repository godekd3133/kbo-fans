# 2026-06-19 More Tab Icon Reference

## Reference Sources

- Sofascore home / leagues screen: dark sports surface, compact sport category glyphs, pinned list icons, high-contrast active state.
- theScore dark sports feed / scores screen: dense scoreboard rows, small monochrome icons, restrained blue/red status accents.
- Current KBO Fans visual system: 8px cards, neutral charcoal surfaces, team/status color used as a signal rather than decoration.

## Extracted Rules

- Icon wells use fixed geometry: 38px for information rows, 34px for secondary surface rows.
- Glyphs are custom vector shapes, not mixed Material defaults, so stroke weight and optical size stay consistent.
- Default glyph size is 20-21px with rounded caps and joins.
- Icon well radius stays at 8px to match cards.
- Fill uses the target status color at 16% opacity and border at 35% opacity.
- Surface rows may use a lighter 11% fill with no border to avoid over-weighting repeated rows.
- State colors are semantic:
  - Game / push: `AppColors.live`
  - Standings / live surface: `AppColors.accent`
  - Records / brief: `AppColors.positive`
  - News: `AppColors.ballYellow`
- Do not add emoji, decorative English labels, or glossy gradients.

## Implemented More Tab Glyphs

| Kind | Shape | Surface |
| --- | --- | --- |
| `game` | baseball circle with two seam curves | today game, game schedule |
| `standings` | three rising rounded bars | standings shortcut |
| `records` | stat trend polyline with dots | records insight / shortcut |
| `news` | compact document with three text lines | news shortcut / brief |
| `push` | outline bell | push surface |
| `live` | phone outline | Live Activity surface |
| `brief` | three stacked rounded summary lines | baseball brief surface |
| `team` | outline shield | my team edit action |

## QA Artifacts

- `output/playwright/kbo-more-reference/more-tab-icons-top.png`
- `output/playwright/kbo-more-reference/more-tab-icons-scroll-1.png`
- `output/playwright/kbo-more-reference/more-tab-icons-scroll-2.png`
