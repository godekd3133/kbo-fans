# KBO Team Logo Source Audit

Date: 2026-06-19

## Purpose

Team logos materially affect the perceived quality of onboarding, home cards, schedule cards, standings, records, iOS widgets, and Live Activity. The current app-side URL logos are usable for small UI, but the bundled iOS widget logos are too small for native surfaces.

This note records high-resolution logo source candidates found through official pages, Google search, and Pinterest-adjacent discovery.

## Current State

- Flutter screens use `KboTeam.logoUrl` from KBO CDN: `https://6ptotvmi5753.edge.naverncp.com/KBO_IMAGE/emblem/regular/fixed/emblem_{TEAM}.png`.
- KBO CDN fixed logo sizes are mostly `64x41`; `_L` variants are only about `72-87px` wide.
- iOS `TeamLogo_*` assets currently contain a single `logo.png` per team, all measured at `26x17`.
- `docs/APP_SPEC.md` still mentions `_L` CDN logos, but current code uses the transparent base PNG because Lotte `_L` had opaque white corners.

## Source Priority

1. Official team BI/VI pages with downloadable ZIP, AI, PDF, PNG, JPG.
2. Official team static assets embedded in current websites.
3. KBO CDN transparent fixed emblems for small app UI and fallback.
4. Search/Pinterest-discovered vector archives only as discovery or fallback candidates after rights review.
5. Fan reposts, Pinterest pins, and blog mirrors are not primary app-bundle sources unless the asset can be traced back to official material and usage is acceptable.

## Official And High-Quality Candidates

| Team | Best candidate found | Evidence | Notes |
| --- | --- | --- | --- |
| SSG | Official SSG BI ZIP | `ssg_baseballclub_landers_emblem.zip` contains `01_MainLogo(Emblem).ai` at 652 KB | Official page also warns personal use is allowed but commercial use can trigger copyright issues. Use only after release-use review. |
| KT | Official KT BI bundle | `Emblem_ai.6d7ad674.zip` contains `Emblem_ai.ai` at 1.09 MB; `Emblem_jpg.692b85eb.jpg` is `1756x1242` | Static React bundle exposes the official downloadable files. Strong source. |
| NC | Official NC VI ZIP | `NC_Dinos_Emblem.zip` includes RGBA PNGs up to `1001x689` | Strong source; includes transparent PNGs. |
| KIA | Official KIA BI download JPGs | `wordmark.jpg` `1200x400`, `initial-logo.jpg` `624x441`, `emblem.jpg` `700x520` | Official page exposes JPG downloads through the React bundle. Not transparent, but reliable. |
| Samsung | Official Samsung ZIPs | `ai_1_2.zip` contains AI files; `jpg_1_2.zip` contains JPGs at `1755x1241` | Strong source, but AI/JPG naming is old and should be visually checked against current logo usage. |
| Kiwoom | Official Heroes BI PDF/AI | `Kiwoom_heroes_BI.ai` and `Kiwoom_heroes_BI.pdf`, 3 pages each | Strong vector source from official BI page. |
| Doosan | Official website SVG | `meta_img.svg` has `viewBox="0 0 2000 1200"` and embedded `4000x2400` PNG | Strong candidate, but likely a social/meta image. Needs crop/visual verification before using as app logo. |
| LG | Official website/static images plus vector archive fallback | Official page has `logo.png` `129x20` and Azure static team PNGs at `120x120` / one `480x480`; Seeklogo reports `2000x986` AI | No official BI download found yet. Prefer official images for now; use vector archives only after rights/source review. |
| Lotte | Third-party AI / Wikimedia candidates; KBO CDN fallback | Search and Pinterest surface AI mirrors and Wikimedia `728x461` PNG | Official site currently blocks/redirects CLI access. Need browser/manual pass before bundling a high-res asset. |
| Hanwha | Official current PNG plus third-party AI fallback | Official `ci_logo_main.png` is `144x120`; search finds 2025 AI mirror posts | Official public PNG is small. 2025 BI is confirmed by official news, but high-res downloadable official file was not found yet. |

## Pinterest / Google Findings

- Pinterest search surfaces the FoxCG post and individual pins that point to KBO vector/download pages.
- Pinterest is useful for discovery, especially when it links back to Seeklogo, official pages, or blog posts with AI attachments.
- Pinterest itself should not be treated as a source of truth for app-bundled assets.
- Search result quality was best with queries like:
  - `site:pinterest.com KBO 야구 로고 ai png`
  - `KBO 구단 로고 AI PNG 고화질 다운로드`
  - `{team name} 구단 BI 로고 다운로드 AI 공식`
  - `KBO {team name} logo vector SVG PNG`

## Implementation Recommendation

- Keep `KboTeam.logoUrl` on the transparent KBO CDN base PNG for now because it is consistent and avoids the Lotte `_L` white-corner issue.
- Replace iOS `TeamLogo_*` native assets from official/high-quality sources first, because current `26x17` files are the weakest surface.
- Generate normalized transparent PNGs at a stable box size, such as `256x256` or `512x512`, from vector or high-resolution sources.
- Preserve aspect ratio and transparent padding instead of stretching logos into a uniform shape.
- Keep a local, uncommitted source cache for original ZIP/AI/JPG files if rights are uncertain; commit only normalized app-safe outputs after approval.
- For release builds, document trademark/copyright status before bundling non-KBO-CDN logo files.

## Reusable Audit Command

Use this command before replacing team logo assets:

```bash
python3 scripts/audit_team_logo_sources.py --output artifacts/team-logo-source-audit
```

The script writes:

- `candidate-summary.csv` / `candidate-summary.json`: official, KBO CDN, Google/Pinterest-discovered reference candidates.
- `zip-entries.csv`: dimensions and file types for image files inside official ZIP packages.
- `current-ios-team-logo-sizes.csv`: current `TeamLogo_*` bundle dimensions.
- `README.md`: a human-readable report that shows which candidate is meaningfully better than the current bundled logo.

The script uses official/high-resolution URLs from this audit, keeps Pinterest as discovery-only metadata, and falls back to `curl` when Python certificate validation fails on a team site.

## Next Step

The most practical next pass is a native-logo replacement pipeline:

1. Fetch official/high-quality source files into a temp or untracked source folder.
2. Render/crop each team logo into transparent square PNGs.
3. Replace `app/ios/Runner/Assets.xcassets/TeamLogo_{TEAM}.imageset/logo.png`.
4. Run iOS widget/Live Activity visual verification.
5. Update source notes if any team required a non-official fallback.
