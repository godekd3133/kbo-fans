---
name: kbo-release-flow
description: Use when preparing commits, pushes, numeric release tags, release notes, or friend/TestFlight-facing release steps for this repository.
---

# KBO Release Flow

## When to use
- Commit/push requests
- Numeric release tag creation
- Release note or changelog prep
- TestFlight or friend-distribution prep

## Rules
- Use Korean commit messages.
- For version/tag/release-note work, use `kbo-version-release` and follow `docs/VERSIONING.md` first.
- Update `README.md`, `CHANGELOG.md`, and `docs/WORKLOG.md` when user-visible behavior or run/release flow changes.
- Every version/release change must also update `app/assets/bootstrap/patch_notes.md` for in-app patch notes.
- Update `docs/APP_SPEC.md` when UX flow or API contract changes.
- `APP_ENV=release` builds must pass `scripts/release-api-health-check.sh` before artifact creation or device install.
- If production API is not `https://api.kbofans.com/api`, set `RELEASE_API_BASE_URL` or pass the GitHub Actions `release_api_base_url` input.
- If default `origin` SSH push fails, use `git@github-personal:godekd3133/kbo-fans.git`.
- Use plain numeric tags only, e.g. `0.0.11`. Do not create `*-preview*` tags or GitHub prereleases unless the Director explicitly changes the policy.
- If the Director says "이어서 해", continue autonomously and decide whether to version up or reinforce the current GitHub release notes based on the actual diff.

## Validation
- `git status --short --branch`
- `git log --oneline --decorate -5`
- App checks when relevant:
  - `cd app && fvm flutter analyze`
  - `cd app && fvm flutter test`
- Release API checks when relevant:
  - `scripts/release-api-health-check.sh`
- Backend checks when relevant:
  - `python3 -m compileall backend/src`
  - `backend/.venv/bin/pytest -q`

## Release docs
- TestFlight checklist: `docs/IOS_TESTFLIGHT_CHECKLIST.md`
- Android signing: `docs/ANDROID_SIGNING_GUIDE.md`
- Work history: `docs/WORKLOG.md`
