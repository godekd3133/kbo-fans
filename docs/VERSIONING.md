# Versioning And Release Policy

> Created: 2026-05-20
> Updated: 2026-06-30

## Current Baseline

- Active release line: `0.1.x`
- Flutter app version: `0.1.10+77`
- Current release tag: `0.1.10`
- Preview suffixes are not used. Do not create `*-preview*` tags or GitHub prereleases for this repository.
- Historical preview/prerelease tags were rewritten into plain numeric releases on 2026-05-20 by explicit Director request.

## Version Formats

- App version: `MAJOR.MINOR.PATCH+BUILD` in `app/pubspec.yaml`
- Git tag: `MAJOR.MINOR.PATCH`
- In-app patch note heading: app version with build, for example `0.0.28+28 - Current Boxscore & Records Guard`

## Bump Rules

- Pre-1.0 release checkpoints increment `PATCH` by one for every tester-facing or release-facing checkpoint.
- Build number increments monotonically with each tester-facing iOS build.
- `MINOR` is reserved for a larger product milestone after the current early tester line is stable.
- The Director may explicitly promote a release to a minor milestone; `0.1.0+67` is the first such tester-facing milestone after `0.0.66+66`.
- `MAJOR` is reserved for post-1.0 product, data, or release contract changes that are incompatible with the previous stable line.
- Do not use `-preview`, `-alpha`, `-beta`, or `-rc` suffixes unless the Director explicitly changes this policy.

## Mandatory Version Checklist

Every version or release change must update these surfaces in the same work unit:

- `app/pubspec.yaml` when the app version or build number changes.
- `CHANGELOG.md` for public/user-visible release history.
- `app/assets/bootstrap/patch_notes.md` for in-app update notes. Keep these written for users: focus on visible screen, notification, data, and interaction changes. Put deployment checkpoints, server/workflow details, and verification notes in `CHANGELOG.md`, GitHub Release notes, and `docs/WORKLOG.md` instead.
- GitHub Release title and body.
- `docs/WORKLOG.md` for engineering decisions and verification.
- `README.md`, `AGENTS.md`, `CLAUDE.md`, or `.claude/skills/` when release workflow rules changed.

## In-App Update Notes Writing Standard

- 앱 안 `업데이트 소식`은 유저가 업데이트 직후 바로 읽는 문장으로 쓴다.
- 기술 단어, endpoint, 배포 checkpoint, 테스트명, 내부 구현 설명은 넣지 않는다.
- 큰 기능만 쓰지 말고 유저가 체감하는 작은 변경, 구체적인 버그 수정, 성능/안정성 개선도 남긴다.
- 권장 bullet prefix:
  - `새로워졌어요:` 새 화면, 새 기능, 새 알림, 새 위젯
  - `고쳤어요:` 사용자가 겪던 구체적인 문제와 해결 결과
  - `빨라졌어요:` 로딩, 갱신, 화면 전환, 캐시, 스크롤 체감 개선
  - `작게 다듬었어요:` 문구, 간격, 아이콘, 탭, 작은 화면 표시 개선
- `여러 버그 수정`, `성능 개선`, `기타 개선`처럼 뭉뚱그린 문구만 쓰지 않는다. 가능하면 `어디에서 무엇이 좋아졌는지`를 한 문장으로 적는다.
- 정렬 순서는 유저 영향도가 큰 변화, 중요한 버그 수정, 성능/안정성, 작은 polish 순서를 기본으로 한다.

## Release Rules

- Decide the target version before creating commits or tags.
- Tags are immutable after publish. Do not force-update, delete, or recreate published tags unless the Director explicitly approves a historical release rewrite.
- When historical releases are rewritten, update this release map, GitHub releases, in-app update notes, and changelog in the same pass.
- GitHub releases should be normal releases, not prereleases, under the current no-preview policy.
- Mark only the newest numeric release as `Latest`.
- `APP_ENV=release` artifacts default to backend API data mode and must carry the production `API_BASE_URL` for screen data, push, and Live Activity token registration. Run `scripts/release-api-health-check.sh` before release-facing validation.
- Tester-facing iOS TestFlight releases must include the external tester handoff in the same release closeout: wait for the uploaded build to become `VALID`, attach the newest build to the `External Testers` group, remove superseded older build relationships from that group, submit Beta App Review if no submission exists, and report external installability separately from upload/processing.
- When the Director says "이어서 해", decide autonomously whether the current work deserves a new numeric version or should only amend/rewrite the current GitHub release notes. Prefer a new version when app behavior, API behavior, user-visible UI, or in-app update notes change.

## Numeric Release Map

- `0.0.1`: initial project scaffold, Flutter/FastAPI baseline, MVP screen skeletons.
- `0.0.2`: early run scripts, documentation, and first widget/live-activity direction cleanup.
- `0.0.3`: my-team first UX, Dynamic Island/Live Activity iteration, schedule/detail polish.
- `0.0.4`: records, player detail, game detail, and distribution baseline.
- `0.0.5`: notification, Firebase, Android/iOS signing, and tester preparation pass.
- `0.0.6`: compact scoreboard, widget/live-activity data, and API-first release guard improvements.
- `0.0.7`: final early rolling snapshot before the organized release-routine cleanup.
- `0.0.8`: release routine baseline, direct-primary path separation, release health gate, and records snapshot baseline.
- `0.0.9`: home secondary fan-out removal and API-first/direct-primary documentation cleanup.
- `0.0.10`: direct-primary historical records recovery, WebForms session handling, and startup remote prefetch removal.
- `0.0.11`: lineup tab request fan-out reduction, web resume refresh scope fix, patch-note cleanup, and current app build `0.0.11+11`.
- `0.0.12`: home KBO brief, records image fallback, wRC+ records label, home quick item player images, pre-game score hiding, app-wide micro motion, finished-game detail snapshot-first reads, and update-loop load reduction with current app build `0.0.12+12`.
- `0.0.13`: fixed KBO emblem URLs, exact-season records overview bootstrap policy, current-season team/player snapshot freshness, stale bundled records cleanup, KT 2026 snapshot refresh, and 2026 home-run leaderboard snapshot with current app build `0.0.13+13`.
- `0.0.14`: app-side device and bundled team/player snapshot freshness guard for current-season records, legacy cache envelope migration, and regression tests with current app build `0.0.14+14`.
- `0.0.15`: standings bootstrap exact-season cleanup, current-season standings freshness guard, records overview bootstrap generation from stored snapshots, selected historical records overview snapshots, stale historical standings bundle removal, web local API default hardening, and KT 2026 bundle refresh with current app build `0.0.15+15`.
- `0.0.16`: backend current-date scoreboard and current-season/month schedule, standings, records overview, and leaderboard snapshot freshness guard, app home scoreboard cache TTL, current-season records/team-player freshness cleanup, retired-player leaderboard preservation, and current app build `0.0.16+16`.
- `0.0.17`: direct KBO routing guard for local native explicit direct-primary builds only, provider/widget background API route alignment, Android/Web release API health-gated run paths, complete records-overview device snapshot guard, current API failure masking prevention, and provider routing/API cache regression tests with current app build `0.0.17+17`.
- `0.0.18`: historical backend leaderboard snapshots for 2011 ERA and 2013 HR with retired top-leader regression coverage, release-gated web wrapper, Android/Web release action wrappers, and current app build `0.0.18+18`.
- `0.0.19`: current/live game detail stale snapshot masking guards for boxscore, lineup, relay, and team records, `codex-run.sh web` release API health-gated default command, `web-dev` debug split, release execution documentation cleanup, and current app build `0.0.19+19`.
- `0.0.20`: current/future home aggregate fail-fast for schedule, standings, and records overview section failures, historical home partial fallback preservation, records overview crawler/snapshot featured canonicalization, device snapshot v3 rank-one guard for records overview/leaderboards, runtime data docs/skill alignment, and current app build `0.0.20+20`.
- `0.0.21`: app API cache validator path for records overview/leaderboards, web/API cache key invalidation for rank-gap records payloads, 2013 AVG leaderboard snapshot recovery, records overview error card, team records error messaging, app-wide provider retry disablement, and current app build `0.0.21+21`.
- `0.0.22`: current-date/current-season app API requests no longer reuse fresh local API cache after backend failure, backend current scoreboard/schedule/standings/records overview/leaderboards no longer return snapshots after crawler failure, home first paint no longer renders separate today-scoreboard local cache, 2026-05-20 cancellation/current snapshot refresh, and historical cached-first/snapshot behavior is preserved, with current app build `0.0.22+22`.
- `0.0.23`: backend current-season team players, team stats, and player detail no longer return backend snapshots or stale in-memory fallback after crawler failure, historical team/player snapshots remain available, GitHub Actions app artifacts now wait for backend pytest first, and current app build `0.0.23+23`.
- `0.0.24`: backend `/scoreboard/home` and `/scoreboard/compact` now use lightweight schedule + main list summaries without per-game scoreboard detail fan-out, full scoreboard/game detail keep detailed View1 enrichment, current home scoreboard keeps fail-visible snapshot policy, and current app build `0.0.24+24`.
- `0.0.25`: app scoreboard, relay summary, my-team card, and local KBO brief now distinguish missing H/E/B team totals from real zero values, display unavailable totals as `-` or hide that row, and current app build `0.0.25+25`.
- `0.0.26`: home secondary aggregate provider now waits until the first scoreboard data frame, home refresh timers are signature-stable across unrelated rebuilds, backend current data routes share `api/runtime_services.py` singletons to reuse TTL caches across sibling endpoints, home skeleton spacing avoids small-card overflow, and current app build `0.0.26+26`.
- `0.0.27`: LIVE home/widget summary scoreboard paths now prefer valid KBO main-list scores over schedule/detail fallback zeroes so in-progress games cannot stay at stale 0:0, with regression coverage and current app build `0.0.27+27`.
- `0.0.28`: current/live boxscore no longer borrows same-team adjacent game rows when the official payload is empty, historical adjacent canonical-id correction keeps requested `gameId` and records `sourceGameId`, records overview/leaderboards are rank-normalized before API response, with regression coverage and current app build `0.0.28+28`.
- `0.0.29`: schedule month navigation keeps selected state across selected-tab retaps and load failures, cancelled games preserve KBO status labels such as rain cancellation across app/backend/widget surfaces, direct-primary relay/boxscore player imagery and Korean name matching are tightened, relay passed-ball classification is explicit, Lotte logo uses the transparent emblem asset, and current app build `0.0.29+29`.
- `0.0.30`: TestFlight first-run crash fix for missing my-team widget storage values, iOS background refresh plist declarations for widget/push surfaces, uploaded as build `0.0.30+30` and superseded by `0.0.31`.
- `0.0.31`: push / Live Activity backend deployment preparation, immediate game-start notification defaults, iOS Workmanager BGTask launch handler registration for `kbo-widget-periodic`, direct lineup recovery through `GetLineUpAnalysis`, relay lineup labels, live my-team follow state polish, live-game ticket-info hiding, game-detail back fallback, and current app build `0.0.31+31`.
- `0.0.32`: 마이팀 live 경기 감지 시 Live Activity / Dynamic Island follow target 자동 선택, 경기 시작 기본 push topic 구독, backend `deliveryModes` topic 계산 정렬, 문자중계 focus/선수 라벨 보정, and current app build `0.0.32+32`.
- `0.0.33`: TestFlight push / Live Activity token registration build using the deployed AWS HTTP smoke backend `API_BASE_URL`, with a narrow temporary ATS exception for that ALB host, and current app build `0.0.33+33`.
- `0.0.34`: Relay foreground refresh cadence shortened to 15 seconds, game detail resume refresh keeps the last valid detail on transient failure, relay player images are reinforced from profile/current-at-bat sources, my-team live badge is shortened to `LIVE`, and current app build `0.0.34+34`.
- `0.0.35`: `at_bat` immediate push moment, relay-seq based backend homerun push, Live Activity current-at-bat payload enrichment, live boxscore placeholder guard across direct/backend paths, and current app build `0.0.35+35`.
- `0.0.36`: TestFlight iOS bundle now includes Firebase `GoogleService-Info.plist` for push initialization, API diagnostics shows release push failure reasons, backend topic resubscribe operation is documented in release notes, and current app build `0.0.36+36`.
- `0.0.37`: release/dev apps with a selected my-team now run one-time notification permission plus FCM registration sync automatically, live push/Live Activity cadence is aligned to 8 seconds, `game_start_soon` and `hit` moments are included in push topics, push registry preserves current followed game ids, Live Activity / Dynamic Island visual structure is aligned with the home score card, and current app build `0.0.37+37`.
- `0.0.38`: push moment routing polish for `game_start_soon`, explicit app/backend tests for `game_start_soon` and `hit` topic contracts, and current app build `0.0.38+38`.
- `0.0.39`: release/TestFlight apps no longer backfill local scoreboard/relay event notifications when the app is opened or focused; app-outside notifications are left to backend FCM/APNs, with current app build `0.0.39+39`.
- `0.0.40`: home resume refresh keeps the last valid scoreboard on transient failure, live relay/backend sync cadence moves to 5 seconds, off-day home CTAs, smoother tab/native swipe transitions, season standings, expanded generated baseball visuals, Pretendard font, my-team brief polish, and baseball-info push smart daily planning ship with current app build `0.0.40+40`.
- `0.0.41`: tab transitions now follow actual tab order direction, schedule month jumps use smoother ease-in-out PageView motion, generated visual/retry-state docs are reinforced, and current app build `0.0.41+41`.
- `0.0.42`: schedule and standings generated baseball visuals are integrated into the functional header/summary rail instead of separate strips, secondary-screen motion is reinforced for diagnostics/patch notes/lineup, integrated visual UI mockup docs are preserved, and current app build `0.0.42+42`.
- `0.0.43`: common visual resource rail ships across home, game detail, schedule, standings, records, notifications, and onboarding; `casual_*.webp` assets are explicitly included in the release manifest; `0.0.42` TestFlight processing build is superseded by the current source-aligned `0.0.43+43` build.
- `0.0.44`: representative artwork constants are cut over to casual WebP assets, the release manifest drops the older PNG representative artwork entries, and `0.0.43` TestFlight processing build is superseded by the current source-aligned `0.0.44+44` build.
- `0.0.45`: no app behavior change; reuploads the `0.0.44` WebP-only visual asset configuration as TestFlight build `0.0.45+45` so Apple processing, Git tag, and GitHub Release checkpoints align again.
- `0.0.46`: home reference dashboard TestFlight upload checkpoint, superseded before GitHub release/tag by `0.0.47` after post-upload home UI compact fixes.
- `0.0.47`: home reference dashboard TestFlight upload checkpoint, superseded before GitHub release/tag by `0.0.48` after bottom-tab label/route alignment fixes.
- `0.0.48`: home reference dashboard TestFlight upload checkpoint, superseded before GitHub release/tag by `0.0.49` after final source sync and bottom-tab label confirmation.
- `0.0.49`: home reference dashboard TestFlight upload checkpoint, superseded before GitHub release/tag by `0.0.50` after patch-note and news-tab source sync.
- `0.0.50`: home reference dashboard TestFlight/backend deploy checkpoint, superseded before GitHub Release by `0.0.51` after post-deploy source sync.
- `0.0.51`: home reference dashboard TestFlight upload checkpoint, superseded before GitHub release/tag/backend deploy by `0.0.52` after home header action icon source sync.
- `0.0.52`: home reference dashboard TestFlight upload checkpoint, superseded before GitHub release/tag/backend deploy by `0.0.53` after reference team logo asset source sync.
- `0.0.53`: home reference dashboard release checkpoint, superseded before GitHub release/tag/backend deploy by `0.0.54` after schedule/records/motion UX and game-detail scorebug source sync.
- `0.0.54`: home reference dashboard TestFlight upload/Git tag checkpoint, superseded before GitHub Release/backend deploy by `0.0.55` after home lower-info and team-record navigation source sync.
- `0.0.55`: home is rebuilt around the reference dashboard flow with KBO brand mark, my-team brief, today games, recent flow, standings snapshot, insight/quick-info lower sections, and team-record tap targets from recent-flow/standings rows; bottom tabs align as home/game/records/news/more with a real `/news` brief screen; schedule calendar scrolling, records information density, common motion, and game-detail scorebug stability are reinforced; backend `/home` adds `standingsPreview`; current app build `0.0.55+55`.
- `0.0.56`: home KBO brief score strip is densified around team labels, score, B-S-O dots, and base diamond; mini cards prioritize player performance, team trend, record radar, and pitcher check items before generic fallback cards; TestFlight build `0.0.56+56` upload checkpoint, superseded before GitHub Release/backend deploy by `0.0.57` after the home info-pack flow reorder.
- `0.0.57`: home lower information flow is reordered to standings, insight pack, quick info, and recent flow; includes the `0.0.56` KBO brief strip/card ordering checkpoint and aligns TestFlight, Git tag, GitHub Release, backend deploy, and topic resubscribe on build `0.0.57+57`.
- `0.0.58`: news and records tabs are rebuilt around editorial brief/signals and league briefing flows; onboarding, more/settings, game detail, boxscore, lineup, and relay surfaces share bundled team logo imagery and richer player image rows; backend/home brief record items carry player image fallback data and off-day CTA routes to schedule; current app build `0.0.58+58`.
- `0.0.59`: records tab premium data-room polish tightens headline leader, metric spotlight, and tabbed TOP3 leaderboard density; 2026 records overview bootstrap/snapshots are refreshed; onboarding CTA, Dev Console capture flag, notification inbox malformed-payload recovery, and push receipt test script are reinforced; current app build `0.0.59+59`.
- `0.0.60`: Live Activity current-at-bat mapping is corrected for top/bottom half innings, relay-driven batter average / pitcher ERA / pitch count / B-S-O is included on the Lock Screen surface, release/direct builds with `API_BASE_URL` keep remote push registration enabled, relay base diamonds parse compact base-state strings, records tab stadium bitmap backdrop ships, and 2026 records overview bootstrap/snapshot data is refreshed again; current app build `0.0.60+60`.
- `0.0.61`: backend API data mode becomes the default for local/dev/release/web/native builds and scripts/CI artifacts; direct KBO remains an explicit parser/debug path; game-detail live follow uses a single push relay CTA; live boxscore can show current batter/pitcher context before official rows exist; Live Activity batting average folds today's completed at-bats into the season AVG, app resume/widget Live Activity sync preserves current-at-bat stats, the Lock Screen/Dynamic Island matchup layout is tightened, Doosan 2025 and Samsung high-resolution logo assets ship, home standings taps open the standings overview, schedule/news/records surfaces receive density polish, and June 2026 schedule / records fixtures are refreshed; current app build `0.0.61+61`.
- `0.0.62`: release sync checkpoint for the `0.0.61` backend API default / Live Activity real-time AVG build; Push / Live Activity preflight now checks the current API base URL handoff structure, and TestFlight, GitHub Release, backend deploy, topic resubscribe, and release API health evidence are realigned on current app build `0.0.62+62`.
- `0.0.63`: reuploads the `0.0.62` backend API default / Live Activity real-time AVG / live boxscore context / push relay CTA release state as TestFlight build `0.0.63+63`; AWS backend API/worker runtime now receives KBO relay credentials through Secrets Manager so live relay API health is part of the release gate.
- `0.0.64`: followed-game push subscriptions prefer `*_GAME_<gameId>` topics for game moments, backend game moment and lineup push sends include matching game-specific topics, app diagnostics can request a registered-device remote push self-test without bundling `PUSH_SYNC_SECRET`, in-app update notes use user-facing wording, and backend deploy, topic resubscribe, TestFlight upload, external tester handoff, and GitHub Release evidence are realigned on current app build `0.0.64+64`.
- `0.0.65`: reuploads the `0.0.64` 경기별 push topic / pregame Live Activity / remote push self-test release state as TestFlight build `0.0.65+65` because App Store Connect already had build `64`; the iOS Widget extension build settings now inherit Flutter `Generated.xcconfig` so Runner and Widget versions stay aligned.
- `0.0.66`: includes the followed-game push topic scope correction after `0.0.65`, narrowing immediate game moments to selected-game `*_GAME_<gameId>` topics and keeping `summary` / `liveOnly` / `off` moments out of immediate remote push topic registration.
- `0.1.0`: Director-requested minor milestone reupload of the `0.0.66` followed-game push topic scope correction as TestFlight build `0.1.0+67`, with backend deploy, topic resubscribe, external tester handoff, and GitHub Release evidence realigned on the new milestone tag.
- `0.1.1`: remote push receipt observability release. The app reports handled remote push receipts back to the backend, and push config diagnostics expose recent receipt summaries without raw device tokens so followed-game notification receipt can be verified after TestFlight installation.
- `0.1.2`: push device-state diagnostics release. App push registration reports notification authorization and APNs readiness to the backend, backend config-status exposes redacted device summaries with separate app-registration and topic-sync timestamps, and followed-game receipt debugging no longer has to guess whether the installed build has re-registered.
- `0.1.3`: push installation identity release. App push registration includes a stable installation id, backend replaces stale FCM tokens for the same app installation, and config-status exposes redacted installation suffixes so followed-game push targets can be matched to the current installed app.
- `0.1.4`: design-reference consistency release. News, schedule, and records design QA references that were already linked from docs are committed, and the notification inbox reference generator is added for repeatable future UI polish. No app runtime, backend API, push, or Live Activity behavior changes.
- `0.1.5`: followed-game moment coverage release. Selected-game follow subscriptions include every enabled game moment as `*_GAME_<gameId>` topics even when the saved delivery mode is `summary` or `liveOnly`, while team/all-game subscriptions still require `immediate`.
- `0.1.6`: my-team automatic game notification release. My-team subscriptions include every enabled game moment on team topics without requiring `푸쉬 중계 받기`, followed other-team games add only the selected GAME topic, scheduler scoreboard diff sends `lineup_opened`, the sync worker schedules KST smart daily `baseball_info`, and the missing notification-inbox reference image is committed.
- `0.1.7`: notification copy and screen-flow polish release. Onboarding shows a submitting state and removes the standalone hero image, More becomes an action-focused hub, player images are restored across detail/records surfaces, push/Live Activity/widget copy uses fan-facing short team names, and hit/homerun/scoring/reversal/cancelled/suspended messages are normalized for live game context.
- `0.1.8`: live alert and game-detail freshness release. My-team game topics now include every game moment regardless of saved delivery/off settings, iOS 17.2+ push-to-start Live Activity registration and backend APNs start dispatch are added, stale push baselines are re-anchored without backfill, home-to-detail navigation waits for fresh detail/tab data, live detail tab switches refresh visible data immediately, live boxscore context can show relay-derived at-bats/hits/AVG, lineup/player image fallbacks are reinforced, and Live Activity/Dynamic Island/widget text fitting is tightened.
- `0.1.9`: widget/settings/game-surface polish release. In-app update prompts, expanded iOS/Android widgets, light/system/dark theme mode, simplified settings, push notification presets, Jua typography, home full-list sections, live-game shortcuts, relay/boxscore visual cleanup, highlight fallback links, final-game at-bat clearing, and push topic preference enforcement are bundled with current app build `0.1.9+76`.
- `0.1.10`: matchup schedule, KBO brief, notification detail, and boxscore density release. Schedule matchup view, richer home/news KBO brief items, my-team record summary, push detail levels, lineup/baseball-info push copy correction, light/dark contrast fixes, boxscore team comparison and extended stats, and selected branch integrations are bundled with current app build `0.1.10+77`.

## GitHub Release Note Template

```markdown
## Summary
- One or two lines explaining why this version exists.

## User-facing changes
- Feature or UX changes visible in the app.

## Data / release changes
- API, snapshot, widget, notification, or build pipeline changes.

## Verification
- Commands or checks that passed.

## Notes
- Known limits, superseded release notes, or tester instructions.
```
