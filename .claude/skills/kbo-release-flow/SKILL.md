---
name: kbo-release-flow
description: Use when preparing commits, pushes, preview tags, release notes, or friend/TestFlight-facing release steps for this repository.
---

# KBO Release Flow

## When to use
- Commit/push requests
- Preview tag creation
- Release note or changelog prep
- TestFlight or friend-distribution prep

## Rules
- Use Korean commit messages.
- Update `README.md`, `CHANGELOG.md`, and `docs/WORKLOG.md` when user-visible behavior or run/release flow changes.
- Update `docs/APP_SPEC.md` when UX flow or API contract changes.
- If default `origin` SSH push fails, use `git@github-personal:godekd3133/kbo-fans.git`.
- Keep preview tags sequential and explicit, e.g. `0.0.2-preview`.

## Validation
- `git status --short --branch`
- `git log --oneline --decorate -5`
- App checks when relevant:
  - `cd app && fvm flutter analyze`
  - `cd app && fvm flutter test`
- Backend checks when relevant:
  - `python3 -m compileall backend/src`
  - `backend/.venv/bin/pytest -q`

## Release docs
- TestFlight checklist: `docs/IOS_TESTFLIGHT_CHECKLIST.md`
- Android signing: `docs/ANDROID_SIGNING_GUIDE.md`
- Work history: `docs/WORKLOG.md`
