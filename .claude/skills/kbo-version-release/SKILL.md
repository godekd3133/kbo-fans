---
name: kbo-version-release
description: Use when changing KBO Fans app versions, creating GitHub releases or tags, rewriting release notes, or updating in-app update notes.
---

# KBO Version Release

## Start Here

- Read `docs/VERSIONING.md` first.
- Use this with `kbo-release-flow` for commit, push, tag, or GitHub release work.

## Required Routine

1. Decide the target version before editing.
2. If app version/build changes, update `app/pubspec.yaml`.
3. Update public notes in `CHANGELOG.md`.
4. Update in-app notes in `app/assets/bootstrap/patch_notes.md` with user-facing wording only. Focus on visible screen, notification, data, and interaction changes; keep deployment checkpoints, server/workflow details, and verification notes in `CHANGELOG.md`, GitHub Release notes, and `docs/WORKLOG.md`.
5. Update `docs/WORKLOG.md` with the versioning/release decision and verification.
6. If historical releases are split or rewritten, update `docs/VERSIONING.md` release map and keep every numeric release represented in app update notes.
7. If workflow rules changed, update `README.md`, `AGENTS.md`, `CLAUDE.md`, `.claude/SKILL_REFERENCE.md`, and related skills.
8. Create an immutable tag only after commits are final.
9. Create or rewrite GitHub release notes from the changelog and in-app update notes.
10. For tester-facing iOS releases, after TestFlight upload and Apple processing reach `VALID`, attach the newest build to `External Testers`, remove superseded older build relationships from that group, and submit Beta App Review when needed before closing the release.
11. When the Director says "이어서 해", decide whether to create the next numeric version or only reinforce the current release notes. Use a new version for app behavior, API behavior, visible UI, or in-app update-note changes; use release-note reinforcement for wording-only cleanup.

## Version Rules

- App version format: `MAJOR.MINOR.PATCH+BUILD`.
- Git tag format: `MAJOR.MINOR.PATCH`.
- Use plain numeric releases from `0.0.1` upward while the app is in early tester mode.
- Do not create `*-preview*` tags, GitHub prereleases, or preview train names unless the Director explicitly changes the policy.
- Do not force-update, delete, or recreate published tags unless the Director explicitly approves a historical release rewrite.
- "이어서 해" means continue autonomously through versioning/release-note judgment without asking unless the choice is risky or ambiguous.

## Minimum Verification

- `git status --short --branch`
- App checks when code changed:
  - `cd app && fvm flutter analyze`
  - Relevant `cd app && fvm flutter test ...`
- Release checks when creating release artifacts:
  - `scripts/release-api-health-check.sh`
- GitHub checks after publish:
  - `gh release list --repo godekd3133/kbo-fans --limit 20`
  - `git ls-remote git@github-personal:godekd3133/kbo-fans.git refs/heads/main refs/tags/<tag>`
