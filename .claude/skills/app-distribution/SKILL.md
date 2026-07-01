---
name: app-distribution
description: Use when preparing KBO Fans for friend or tester distribution, including web-first sharing, Android release signing, Google Play internal testing, and iOS TestFlight preparation.
---

# App Distribution

Use this skill when the goal is to let friends or testers try the app.

## Routing

- Fastest share: web first
- Android install: release signing + Play internal testing
- iPhone install: TestFlight

## Read These Docs

- `docs/DISTRIBUTION_GUIDE.md`
- `docs/ANDROID_SIGNING_GUIDE.md`
- `docs/IOS_TESTFLIGHT_CHECKLIST.md`

## Project Rules

- Android release signing is based on `app/android/key.properties` when present.
- Keep `app/android/key.properties`, `*.jks`, and `*.keystore` out of git.
- Use `app/android/key.properties.example` as the template.
- Local release builds may fall back to debug signing, but that is not valid for Play distribution.
- iOS tester distribution should default to TestFlight, not ad-hoc IPA sharing.
- For tester-facing iOS release work, do not stop at TestFlight upload. After App Store Connect processing reaches `VALID`, attach the newest build to the `External Testers` group and submit Beta App Review when no submission exists yet. Do not remove the last approved/installable external build until the newest build is approved or otherwise confirmed installable for external testers. Keep upload success, Apple processing/VALID, external-group assignment, Beta App Review, and actual installability as separate checkpoints.
- iOS runtime/platform support must match the active Xcode version closely enough for destinations to appear.
- Codex app actions do not auto-register from repository scripts; scripts still need manual registration in the app UI.

## Required Follow-Up

When distribution workflow or assumptions change:

1. Update the related `docs/` file
2. Update `docs/WORKLOG.md`
3. Update `AGENTS.md` and `CLAUDE.md` if the change becomes a standing project rule
