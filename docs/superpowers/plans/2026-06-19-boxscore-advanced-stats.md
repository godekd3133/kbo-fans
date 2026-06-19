# Boxscore Advanced Stats Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend the records-link boxscore with optional game-level advanced stats across backend, app parsers, UI, docs, and tests.

**Architecture:** Keep backward-compatible optional fields on existing batter/pitcher row objects. Backend and direct app parsers read source headers when present; app models expose derived getters; UI renders chips only for known values.

**Tech Stack:** Python 3.9-compatible FastAPI backend, Dart/Flutter, Riverpod, existing KBO ASMX parser, existing widget/model/backend tests.

---

## Files

- Modify: `backend/src/kbo_fans_backend/crawlers/boxscore.py`
- Modify: `backend/tests/test_boxscore_crawler.py`
- Modify: `app/lib/data/models/boxscore.dart`
- Modify: `app/lib/data/repositories/api_game_repository.dart`
- Modify: `app/lib/data/repositories/kbo_direct_repository.dart`
- Modify: `app/test/data/models/boxscore_test.dart`
- Modify: `app/test/data/api_client_test.dart`
- Modify: `app/test/data/kbo_direct_repository_test.dart`
- Modify: `app/test/features/game_detail/boxscore_tab_test.dart`
- Modify: `app/lib/features/game_detail/tabs/boxscore_tab.dart`
- Modify: `docs/APP_SPEC.md`
- Modify: `docs/WORKLOG.md`
- Modify: `CHANGELOG.md`

## Tasks

### Task 1: Backend Parser Optional Fields

- [x] Add backend crawler RED test for hitter headers `타석`, `2루타`, `3루타`, `홈런`, `볼넷`, `사구`, `삼진`, `도루` and pitcher headers `투구수`, `실점`.
- [x] Run `backend/.venv/bin/pytest -q backend/tests/test_boxscore_crawler.py` and confirm the new assertions fail.
- [x] Update `BoxscoreCrawler` to parse header maps for hitter/pitcher tables and include optional fields only when known.
- [x] Re-run the backend crawler tests until green.

### Task 2: App Model And API Parser

- [x] Add Dart model RED tests for batter `extraBaseHits`, `totalBases`, `slugging` and pitcher `inningsPitched`, `gameEra`, `gameWhip`.
- [x] Add API parser coverage in an existing app test if practical; otherwise cover via widget test data using new model fields.
- [x] Run `cd app && fvm flutter test test/data/models/boxscore_test.dart --no-pub --reporter expanded` and confirm failures.
- [x] Extend `BatterRecord` and `PitcherRecord` with optional fields and derived getters.
- [x] Extend `ApiGameRepository` parser to read optional JSON fields.
- [x] Re-run model tests until green.

### Task 3: Direct KBO Parser Parity

- [x] Add direct parser RED coverage in `app/test/data/kbo_direct_repository_test.dart` if existing helper access supports it; otherwise add focused model/API parser coverage and keep direct implementation manually aligned.
- [x] Update `_parseHitterTeamFromTables` and `_parsePitcherTeamFromTable` to parse optional headers when present.
- [x] Run targeted direct repository tests that cover boxscore or related parser behavior.

### Task 4: UI Chips

- [x] Add widget RED test that advanced batter and pitcher chips render when optional fields exist.
- [x] Run `cd app && fvm flutter test test/features/game_detail/boxscore_tab_test.dart --no-pub --reporter expanded` and confirm failure.
- [x] Add advanced stat chips to `_buildBatterCard` and `_buildPitcherCard`; hide unknown optional values.
- [x] Re-run boxscore widget tests until green.

### Task 5: Docs And Verification

- [x] Update `docs/APP_SPEC.md`, `docs/WORKLOG.md`, and `CHANGELOG.md`.
- [x] Run format:
  - `cd app && fvm dart format lib/data/models/boxscore.dart lib/data/repositories/api_game_repository.dart lib/data/repositories/kbo_direct_repository.dart lib/features/game_detail/tabs/boxscore_tab.dart test/data/models/boxscore_test.dart test/data/api_client_test.dart test/data/kbo_direct_repository_test.dart test/features/game_detail/boxscore_tab_test.dart`
- [x] Run Flutter tests:
  - `cd app && fvm flutter test test/data/models/boxscore_test.dart test/data/api_client_test.dart test/data/kbo_direct_repository_test.dart test/features/game_detail/boxscore_tab_test.dart --no-pub --reporter expanded`
- [x] Run Flutter analyze:
  - `cd app && fvm flutter analyze lib/data/models/boxscore.dart lib/data/repositories/api_game_repository.dart lib/data/repositories/kbo_direct_repository.dart lib/features/game_detail/tabs/boxscore_tab.dart test/data/models/boxscore_test.dart test/data/api_client_test.dart test/data/kbo_direct_repository_test.dart test/features/game_detail/boxscore_tab_test.dart --no-pub`
- [x] Run backend tests:
  - `backend/.venv/bin/pytest -q backend/tests/test_boxscore_crawler.py backend/tests/test_boxscore_service.py`
  - `python3 -m compileall backend/src/kbo_fans_backend/crawlers/boxscore.py`
- [x] Run `git diff --check`.
- [x] Commit with Korean message.

### Task 6: Dense Boxscore UX Follow-Up

- [x] Add widget RED coverage for team comparison and expandable batter/pitcher detail.
- [x] Add a team comparison card for selected team vs opponent without synthesizing unknown optional rows.
- [x] Add `상세 기록` expansion to batter and pitcher cards while preserving player-detail navigation.
- [x] Surface matched player-profile season mini metrics only when already available.
- [x] Add context badges such as `멀티히트`, `득점 관여`, `무자책`, and `탈삼진 흐름`.
- [x] Update `APP_SPEC`, `WORKLOG`, `CHANGELOG`, and design notes for the denser boxscore surface.
- [x] Run final targeted format, tests, analyze, and `git diff --check`.
- [x] Commit with Korean message.

## Self-Review

- Spec coverage: backend parser, app model/API/direct parser, UI, docs, and tests are covered.
- Placeholder scan: no open TBD/TODO markers.
- Type consistency: optional Dart fields use nullable `int?`; Python payload uses absent keys for unknown optional values.
