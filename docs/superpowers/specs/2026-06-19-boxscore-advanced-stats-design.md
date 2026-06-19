# Boxscore Advanced Stats Design

## Goal

Complete the follow-up for the records-link boxscore by carrying richer game-level stats through the backend, direct app parser, app model, and boxscore UI.

## Scope

This follow-up extends the current boxscore contract with optional fields only. Missing values stay `null` in app models and are hidden in the UI. The app must not synthesize unverified zeros.

## Contract

### Batter rows

Existing fields remain required:

- `order`
- `position`
- `name`
- `atBats`
- `runs`
- `hits`
- `rbi`

Optional fields:

- `plateAppearances`
- `doubles`
- `triples`
- `homeRuns`
- `walks`
- `hitByPitch`
- `strikeouts`
- `stolenBases`

App-derived getters:

- `extraBaseHits`: `doubles + triples + homeRuns`, only when at least one extra-base field is known
- `totalBases`: singles + 2B + 3B + HR, only when extra-base fields are known
- `slugging`: `totalBases / atBats`, only when `atBats > 0`

### Pitcher rows

Existing fields remain required:

- `name`
- `innings`
- `hits`
- `strikeouts`
- `walks`
- `earnedRuns`
- `decision`

Optional fields:

- `pitchCount`
- `runs`

App-derived getters:

- `inningsPitched`: decimal innings from KBO innings text
- `gameEra`: `earnedRuns * 9 / inningsPitched`
- `gameWhip`: `(hits + walks) / inningsPitched`

## Source Rules

- Backend `BoxscoreCrawler` should parse known Korean headers when available and keep fallback indexes for the existing core fields.
- App direct KBO mode should mirror backend parsing policy.
- Existing snapshots without optional fields remain valid.
- Current/live official-availability guards stay unchanged.
- `OPS` is not computed from game boxscore in this pass because exact OBP needs denominator fields that may not exist in the current boxscore payload. The UI should show game-level SLG/루타 instead and rely on player detail for season OPS/ERA.

## UI

Boxscore rows should expose richer but compact chips:

- Team comparison:
  - show selected team vs opponent for core counts: 득점, 안타, 타점, 탈삼진
  - show optional comparison rows such as 장타 and 볼넷 only when at least one side has a known source value
- Batter rows:
  - existing chips: production, AVG, AB, H, RBI, R
  - new chips when available: `루타 N`, `장타 N`, `SLG .000`, `볼넷 N`, `삼진 N`, `도루 N`
  - expandable detail: today detail pills, season mini metrics from matched player profile, and context badges such as `멀티히트`, `득점 관여`, `홈런`
- Pitcher rows:
  - existing chips: efficiency, IP, H, K, BB/HBP, ER
  - new chips when available: `투구 N`, `ERA 0.00`, `WHIP 0.00`, `실점 N`
  - expandable detail: pitch count, line stats, season mini metrics from matched player profile, and context badges such as `무자책`, `무실점`, `탈삼진 흐름`

Highlight cards can keep current summaries, but their underlying row cards should carry the richer stats.

## Testing

- Backend crawler test: header-driven payload produces optional batter/pitcher fields.
- App model test: derived batter and pitcher getters compute correctly and return null when source fields are unknown.
- API repository test or model parser coverage: optional fields from backend JSON reach app model.
- Direct repository parser test: optional fields are read from ASMX-style headers when present.
- Boxscore tab widget test: advanced stat chips render when optional values exist and do not render when values are null.
- Boxscore tab widget test: team comparison and expandable batter/pitcher detail render only from known boxscore/player-profile values.

## Acceptance

- Backend and direct app modes share the same optional field names.
- No existing placeholder guard regresses.
- No unverified zeros are shown for unknown optional fields.
- Expanded details and comparison rows must not replace the existing player-detail navigation affordance.
- Targeted backend and Flutter tests pass.
- APP_SPEC, WORKLOG, and CHANGELOG describe the expanded boxscore surface.
