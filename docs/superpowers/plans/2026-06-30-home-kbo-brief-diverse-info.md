# Home KBO Brief Diverse Info Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Expand the home/news KBO brief so the home screen surfaces data-grounded league information such as high-error games, game stat outliers, team batting context, and batting leaders.

**Architecture:** Keep the first home paint unchanged: scoreboard still renders first, and richer information is added only through the delayed `/api/home` aggregate and local `buildLocalHomeAggregate` fallback. Backend and app-local generation should produce the same `HomeKboBriefItem` types so `/home` and `/news` stay aligned without external article crawling.

**Tech Stack:** Python 3.9 FastAPI backend, Flutter/Dart Riverpod app, existing `HomeService`, `HomeKboBriefItem`, `homeAggregateProvider`, pytest, Flutter widget/model tests.

---

### Task 1: Add Backend Brief Items For Errors And Batting Context

**Files:**
- Modify: `backend/src/kbo_fans_backend/services/home.py`
- Test: `backend/tests/test_home.py`

- [ ] **Step 1: Write failing backend tests**

Add tests proving:

```python
def test_kbo_brief_surfaces_high_error_game() -> None:
    service = HomeService.__new__(HomeService)
    brief = service._build_kbo_brief(
        today="2026-06-29",
        my_team=None,
        games=[
            {
                "gameId": "20260629OBLG0",
                "status": "FINAL",
                "inning": "경기종료",
                "stadium": "잠실",
                "away": {"teamId": "OB", "shortName": "두산", "score": 4, "hits": 8, "errors": 3},
                "home": {"teamId": "LG", "shortName": "LG", "score": 6, "hits": 10, "errors": 2},
            }
        ],
        standings=[],
        overview={"leaders": {"avg": [], "hr": []}},
    )
    defense_items = [item for item in brief["items"] if item["type"] == "defense_issue"]
    assert defense_items
    assert defense_items[0]["eyebrow"] == "실책 많은 경기"
    assert defense_items[0]["title"] == "두산-LG 합계 5실책"
    assert defense_items[0]["route"] == "/game/20260629OBLG0"
```

Also add a test that verifies a `defense_rank` item summarizes the day's team error ranking from scoreboard team totals.

```python
def test_kbo_brief_uses_avg_leader_when_available() -> None:
    service = HomeService.__new__(HomeService)
    brief = service._build_kbo_brief(
        today="2026-06-30",
        my_team=None,
        games=[],
        standings=[],
        overview={
            "leaders": {
                "avg": [
                    {"rank": 1, "playerId": "64166", "name": "홍창기", "teamId": "LG", "value": "0.351"}
                ],
                "hr": [],
            }
        },
    )
    avg_items = [item for item in brief["items"] if item["type"] == "batting_leader"]
    assert avg_items
    assert avg_items[0]["title"] == "홍창기 타율 0.351"
    assert avg_items[0]["route"] == "/records/player/64166?season=2026"
```

- [ ] **Step 2: Run backend tests and confirm failure**

Run:

```bash
backend/.venv/bin/pytest -q backend/tests/test_home.py::test_kbo_brief_surfaces_high_error_game backend/tests/test_home.py::test_kbo_brief_uses_avg_leader_when_available
```

Expected: fail because `defense_issue` and `batting_leader` are not generated yet.

- [ ] **Step 3: Implement backend generation**

Add helpers in `HomeService`:

```python
@staticmethod
def _game_total_errors(game: Dict[str, Any]) -> int:
    return HomeService._team_errors(game, "away") + HomeService._team_errors(game, "home")

@staticmethod
def _team_errors(game: Dict[str, Any], side: str) -> int:
    return HomeService._as_int((game.get(side) or {}).get("errors"))
```

Add a high-error candidate inside `_build_kbo_brief` after high-hit games:

```python
high_error_games = [game for game in active_games if self._game_total_errors(game) >= 3]
high_error_games.sort(key=lambda game: self._game_total_errors(game), reverse=True)
if high_error_games:
    game = high_error_games[0]
    add(
        self._kbo_brief_item(
            item_type="defense_issue",
            eyebrow="실책 많은 경기",
            title=(
                f"{self._team_short_name(game, 'away')}-"
                f"{self._team_short_name(game, 'home')} 합계 "
                f"{self._game_total_errors(game)}실책"
            ),
            subtitle=(
                f"{self._team_short_name(game, 'away')} {self._team_errors(game, 'away')}실책 · "
                f"{self._team_short_name(game, 'home')} {self._team_errors(game, 'home')}실책"
            ),
            route=f"/game/{game.get('gameId')}",
            game=game,
        )
    )
```

Add `_build_avg_brief_item` and call it after `_build_record_brief_item`.
Add `_build_error_rank_brief_item` and call it after `defense_issue` generation.

- [ ] **Step 4: Run backend tests**

Run:

```bash
backend/.venv/bin/pytest -q backend/tests/test_home.py
```

Expected: all `test_home.py` tests pass.

### Task 2: Mirror Brief Logic In Local App Aggregate

**Files:**
- Modify: `app/lib/data/models/home_aggregate.dart`
- Test: `app/test/data/models/home_aggregate_test.dart`

- [ ] **Step 1: Write failing Dart model tests**

Add tests proving local fallback creates the same `defense_issue`, `defense_rank`, and `batting_leader` item types.

- [ ] **Step 2: Implement local helpers**

Add `_totalErrors(Game game)`, use `game.away.errors + game.home.errors`, and add local high-error item generation matching backend wording.

- [ ] **Step 3: Add local batting leader item**

Use `overview.avgLeaders.first` to create:

```dart
HomeKboBriefItem(
  type: 'batting_leader',
  eyebrow: '타율 리더',
  title: '${leader.name} 타율 ${leader.value}',
  subtitle: '${leader.teamId} · 시즌 타율 1위',
  route: leader.playerId.isEmpty
      ? '/records'
      : '/records/player/${leader.playerId}?season=${overview.season}',
  teamIds: [leader.teamId],
  imageUrl: imageUrl,
  fallbackLabel: leader.name,
)
```

- [ ] **Step 4: Run Dart model tests**

Run:

```bash
cd app && fvm flutter test --no-pub test/data/models/home_aggregate_test.dart -r expanded
```

Expected: all model tests pass.

### Task 3: Map New Types In Home And News UI

**Files:**
- Modify: `app/lib/features/home/home_screen.dart`
- Modify: `app/lib/features/news/news_screen.dart`
- Test: `app/test/features/home/home_screen_test.dart`
- Test: `app/test/features/news/news_screen_test.dart`

- [ ] **Step 1: Update type mappings**

Add:

```dart
'defense_issue' / 'defense_rank' => records/game-aware visual treatment
'batting_leader' => records filter and record story kind
```

Home badge labels should render `실책` for `defense_issue` and `타율` for `batting_leader`.

- [ ] **Step 2: Add focused widget expectations**

Use existing `HomeKboBriefItem` fixtures to assert the new titles appear and route labels are not hidden.

- [ ] **Step 3: Run focused UI tests**

Run:

```bash
cd app && fvm flutter test --no-pub test/features/home/home_screen_test.dart test/features/news/news_screen_test.dart -r expanded
```

Expected: related tests pass, unless unrelated dirty-worktree compile failures are present; document those separately.

### Task 4: Sync Product Docs

**Files:**
- Modify: `docs/APP_SPEC.md`
- Modify: `docs/WORKLOG.md`
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Update API/UX contract**

Add `defense_issue` and `batting_leader` to KBO brief examples and clarify that team season error ranking needs a verified source before becoming a season leaderboard.

- [ ] **Step 2: Add worklog verification**

Record root cause, implementation, and exact test commands.

- [ ] **Step 3: Run whitespace check**

Run:

```bash
git diff --check -- backend/src/kbo_fans_backend/services/home.py backend/tests/test_home.py app/lib/data/models/home_aggregate.dart app/test/data/models/home_aggregate_test.dart app/lib/features/home/home_screen.dart app/lib/features/news/news_screen.dart docs/APP_SPEC.md docs/WORKLOG.md CHANGELOG.md
```

Expected: no whitespace errors.

---

## Self-Review

- Spec coverage: Covers home exposure, error-heavy games, batting average leader context, news reuse through aggregate, and avoids fake external articles.
- Known scope boundary: Full season team error ranking is not implemented here because current `TeamStatsCrawler` has no team error column. The implemented first step uses confirmed scoreboard team errors from actual games.
- Placeholder scan: No TODO/TBD markers.
- Type consistency: Backend and Dart use `defense_issue`, `defense_rank`, and `batting_leader` consistently.
