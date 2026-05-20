# Versioning And Release Policy

> Created: 2026-05-20

## Current Baseline

- Active release train: `0.1.0-preview`
- Flutter app version: `0.1.0+4`
- Current preview tag: `0.1.0-preview.4`
- Existing `0.0.x` tags are legacy snapshots. Keep the tags immutable unless the Director explicitly asks for a historical rewrite.

## Version Formats

- App version: `MAJOR.MINOR.PATCH+BUILD` in `app/pubspec.yaml`
- Stable Git tag: `MAJOR.MINOR.PATCH`
- Preview Git tag: `MAJOR.MINOR.PATCH-preview.N`
- In-app patch note heading: app version with build, for example `0.1.0+1 - Preview 1`

## Bump Rules

- `preview.N`: same app semver, new internal/tester preview on the current release train.
- `PATCH`: user-visible bug fix or safe polish within the same stable line.
- `MINOR`: feature milestone, data architecture change, release workflow change, or tester-facing bundle that should be understood as a new train.
- `MAJOR`: post-1.0 product, data, or release contract change that is incompatible with the previous stable line.

Pre-1.0 rule:

- Use `0.MINOR.PATCH` intentionally. Do not keep incrementing `0.0.x` once the app scope has moved beyond the original prototype line.
- The first organized preview train after the 0.0.x cleanup is `0.1.0-preview.N`.

## Mandatory Version Checklist

Every version or release change must update these surfaces in the same work unit:

- `app/pubspec.yaml` when the app version or build number changes.
- `CHANGELOG.md` for public/user-visible release history.
- `app/assets/bootstrap/patch_notes.md` for in-app patch notes.
- GitHub Release title and body.
- `docs/WORKLOG.md` for engineering decisions and verification.
- `README.md`, `AGENTS.md`, `CLAUDE.md`, or `.claude/skills/` when release workflow rules changed.

## Release Rules

- Decide the target version before creating commits or tags.
- Tags are immutable after publish. Do not force-update published tags except for an immediate failed release correction before anyone consumes it.
- If the Director explicitly asks to reorganize historical releases, prefer adding retrospective tags and rewriting GitHub release notes over deleting or moving existing tags.
- If a preview was messy, mark it superseded in release notes instead of moving the tag.
- GitHub prerelease should be used for `*-preview.N`.
- Stable release should only be marked latest when it is intended as the current stable tester/user baseline.
- `APP_ENV=release` artifacts must pass the release API health gate before release artifact creation.

## Preview Segmentation Rule

Use separate preview tags when a tester-facing checkpoint changes the behavior class:

- `preview.1`: release train baseline, documentation, version routine, app-visible patch-note surface.
- `preview.2`: request-budget or startup/home loading behavior changes.
- `preview.3`: data correctness fixes, crawler/session behavior, snapshot correctness.
- `preview.4`: detail-screen request fan-out, tab-specific UX correctness, current testable app build.

## Legacy Release Map

- `0.0.1-preview`: initial project scaffold, Flutter/FastAPI baseline, MVP screen skeletons.
- `0.0.1-preview.1`: early run scripts, documentation, and first widget/live-activity direction cleanup.
- `0.0.2-preview`: my-team first UX, Dynamic Island/Live Activity iteration, schedule/detail polish.
- `0.0.2`: records, player detail, game detail, and distribution baseline.
- `0.0.3`: notification, Firebase, Android/iOS signing, and tester preparation pass.
- `0.0.4`: compact scoreboard, widget/live-activity data, and API-first release guard improvements.
- `0.0.5`: final legacy rolling preview cleanup snapshot. Superseded by `0.1.0-preview.N`.
- `0.1.0-preview.1`: organized preview train baseline with release routine, direct-primary path separation, release health gate, and records snapshot baseline.
- `0.1.0-preview.2`: home secondary fan-out and API-first/direct-primary documentation cleanup.
- `0.1.0-preview.3`: direct-primary historical records recovery, WebForms session handling, and startup remote prefetch removal.
- `0.1.0-preview.4`: lineup tab request fan-out reduction, web resume refresh scope fix, and current app build `0.1.0+4`.

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
