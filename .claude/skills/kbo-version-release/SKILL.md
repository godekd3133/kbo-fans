---
name: kbo-version-release
description: Use when changing KBO Fans app versions, creating GitHub releases or tags, rewriting release notes, or updating in-app patch notes.
---

# KBO Version Release

## Start Here

- Read `docs/VERSIONING.md` first.
- Use this with `kbo-release-flow` for commit, push, tag, or GitHub release work.

## Required Routine

1. Decide the target version before editing.
2. If app version/build changes, update `app/pubspec.yaml`.
3. Update public notes in `CHANGELOG.md`.
4. Update in-app notes in `app/assets/bootstrap/patch_notes.md`.
5. Update `docs/WORKLOG.md` with the versioning/release decision and verification.
6. If historical releases are split or rewritten, update `docs/VERSIONING.md` release map and keep every new preview section represented in app patch notes.
7. If workflow rules changed, update `README.md`, `AGENTS.md`, `CLAUDE.md`, `.claude/SKILL_REFERENCE.md`, and related skills.
8. Create an immutable tag only after commits are final.
9. Create or rewrite GitHub release notes from the changelog and in-app patch notes.

## Version Rules

- App version format: `MAJOR.MINOR.PATCH+BUILD`.
- Preview tag format: `MAJOR.MINOR.PATCH-preview.N`.
- Stable tag format: `MAJOR.MINOR.PATCH`.
- Do not keep incrementing legacy `0.0.x` for new preview trains; use the active train in `docs/VERSIONING.md`.
- Do not force-update published tags. If the Director asks to reorganize historical releases, prefer adding retrospective tags and rewriting release notes.

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
