# Boxscore Records Link Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the game-detail boxscore tab act as a clear records-entry surface for matched players while preserving current official-availability guards.

**Architecture:** Keep the existing `BoxscoreTab` data flow and current boxscore/backend contract. Add visible records affordances and tappable highlight cards only when a boxscore row can be matched to a `PlayerProfile`; unmatched rows remain static game-record cards.

**Tech Stack:** Flutter, Dart, Riverpod, go_router, existing `GameBoxscoreData`, `TeamBoxscoreData`, `PlayerProfile`, and widget tests.

---

## File Structure

- Modify: `app/lib/features/game_detail/tabs/boxscore_tab.dart`
  - Add visible records-entry affordances to matched batter/pitcher rows.
  - Make highlight cards tappable when a matched player exists.
  - Add lightweight derived labels from existing boxscore fields.
- Modify: `app/test/features/game_detail/boxscore_tab_test.dart`
  - Keep the placeholder guard test.
  - Add tests for matched vs unmatched records affordance.
  - Add route verification for matched row tap.
- Modify: `docs/APP_SPEC.md`
  - Update boxscore UI notes to mention records-entry affordance for matched players.
- Modify: `docs/WORKLOG.md`
  - Append implementation and verification notes.
- Optional: `CHANGELOG.md`
  - Add a user-visible note if the UI change is completed in this branch.

## Task 1: Matched Player Records Affordance Test

**Files:**
- Modify: `app/test/features/game_detail/boxscore_tab_test.dart`
- Modify: `app/lib/features/game_detail/tabs/boxscore_tab.dart`

- [ ] **Step 1: Write the failing widget test**

Add a test that renders a displayable boxscore with one matched batter and one matched pitcher. It should expect `선수 기록 보기` to be visible for matched rows.

```dart
testWidgets('매칭된 박스스코어 선수는 선수 기록 보기 진입점을 보여준다', (tester) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    _boxscoreHarness(
      boxscore: _displayableBoxscore,
      players: [
        _playerProfile(
          id: '50054',
          teamId: 'KT',
          name: '강백호',
          number: 50,
          playerType: PlayerType.hitter,
        ),
        _playerProfile(
          id: '61023',
          teamId: 'KT',
          name: '김영현',
          number: 60,
          playerType: PlayerType.pitcher,
        ),
      ],
    ),
  );

  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));

  expect(find.text('선수 기록 보기'), findsWidgets);
  expect(find.text('오늘 생산 +14'), findsOneWidget);
  expect(find.text('오늘 효율 +4'), findsOneWidget);
});
```

- [ ] **Step 2: Run the test and verify RED**

Run:

```bash
cd app && fvm flutter test test/features/game_detail/boxscore_tab_test.dart --no-pub --reporter expanded
```

Expected: FAIL because `선수 기록 보기`, `오늘 생산 +14`, and `오늘 효율 +4` are not rendered yet.

- [ ] **Step 3: Implement minimal UI**

In `boxscore_tab.dart`:

- Add a `profile` and `onTap` option to `_HighlightCard`.
- Show `선수 기록 보기` only when a matched player exists.
- Add `오늘 생산 +N` to batter rows and key batter card using `(hits * 3) + (rbi * 2) + runs`.
- Add `오늘 효율 +N` to pitcher rows and key pitcher card using `(strikeouts * 2) - (walks * 2) - (earnedRuns * 3)`.

- [ ] **Step 4: Run test and verify GREEN**

Run:

```bash
cd app && fvm flutter test test/features/game_detail/boxscore_tab_test.dart --no-pub --reporter expanded
```

Expected: PASS.

## Task 2: Unmatched Player Stays Static

**Files:**
- Modify: `app/test/features/game_detail/boxscore_tab_test.dart`
- Modify: `app/lib/features/game_detail/tabs/boxscore_tab.dart`

- [ ] **Step 1: Write the failing widget test**

Add a test that renders the same boxscore with no matching `PlayerProfile`. It should not render the records affordance.

```dart
testWidgets('매칭되지 않은 박스스코어 선수는 선수 기록 보기 진입점을 숨긴다', (tester) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    _boxscoreHarness(
      boxscore: _displayableBoxscore,
      players: const <PlayerProfile>[],
    ),
  );

  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));

  expect(find.text('강백호'), findsWidgets);
  expect(find.text('김영현'), findsWidgets);
  expect(find.text('선수 기록 보기'), findsNothing);
});
```

- [ ] **Step 2: Run the test and verify RED or GREEN**

Run:

```bash
cd app && fvm flutter test test/features/game_detail/boxscore_tab_test.dart --no-pub --reporter expanded
```

Expected: FAIL before Task 1 implementation if it is run together with the matched affordance test. After Task 1 implementation, this verifies the conditional display so unmatched rows remain static.

- [ ] **Step 3: Implement or adjust conditional behavior**

Ensure `_buildBatterCard`, `_buildPitcherCard`, and `_HighlightCard` only show `선수 기록 보기` when a `PlayerProfile` exists.

- [ ] **Step 4: Run test and verify GREEN**

Run:

```bash
cd app && fvm flutter test test/features/game_detail/boxscore_tab_test.dart --no-pub --reporter expanded
```

Expected: PASS.

## Task 3: Matched Row Routes To Player Detail

**Files:**
- Modify: `app/test/features/game_detail/boxscore_tab_test.dart`
- Modify: `app/lib/features/game_detail/tabs/boxscore_tab.dart`

- [ ] **Step 1: Write the failing route test**

Use a `GoRouter` harness. Tap the matched batter affordance or row and verify the route target.

```dart
testWidgets('매칭된 박스스코어 선수 탭은 선수 상세로 이동한다', (tester) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    _boxscoreHarness(
      boxscore: _displayableBoxscore,
      players: [
        _playerProfile(
          id: '50054',
          teamId: 'KT',
          name: '강백호',
          number: 50,
          playerType: PlayerType.hitter,
        ),
      ],
      withRoutes: true,
    ),
  );

  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));

  await tester.tap(find.text('선수 기록 보기').first);
  await tester.pumpAndSettle();

  expect(find.text('player:50054'), findsOneWidget);
});
```

Use this helper in `boxscore_tab_test.dart` so tests create valid profiles:

```dart
PlayerProfile _playerProfile({
  required String id,
  required String teamId,
  required String name,
  required int number,
  PlayerType playerType = PlayerType.hitter,
}) {
  return PlayerProfile(
    id: id,
    teamId: teamId,
    name: name,
    number: number,
    playerType: playerType,
    position: playerType == PlayerType.pitcher ? '투수' : '타자',
    roleLabel: playerType == PlayerType.pitcher ? '투수' : '야수',
    handedness: '',
    heightWeight: '',
    birthDate: '',
    status: PlayerAvailabilityStatus.available,
    rosterGroup: PlayerRosterGroup.entry,
    headlineStat: '',
    secondaryStat: '',
    seasonStats: const [],
    highlights: const [],
    recentGames: const [],
  );
}
```

- [ ] **Step 2: Run the test and verify RED**

Run:

```bash
cd app && fvm flutter test test/features/game_detail/boxscore_tab_test.dart --no-pub --reporter expanded
```

Expected: FAIL if the affordance text is not independently tappable or route harness is not wired yet.

- [ ] **Step 3: Implement route-safe affordance tap**

Ensure matched rows and matched highlight cards route through:

```dart
context.push('/records/player/${player.id}?season=${DateTime.now().year}');
```

The `선수 기록 보기` cue should be inside the existing tappable row/card.

- [ ] **Step 4: Run test and verify GREEN**

Run:

```bash
cd app && fvm flutter test test/features/game_detail/boxscore_tab_test.dart --no-pub --reporter expanded
```

Expected: PASS.

## Task 4: Documentation

**Files:**
- Modify: `docs/APP_SPEC.md`
- Modify: `docs/WORKLOG.md`
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Update `docs/APP_SPEC.md`**

In the boxscore UI section, mention:

- Matched player cards show `선수 기록 보기`.
- Unmatched player rows remain static records.
- Highlight cards use current-game derived labels only.

- [ ] **Step 2: Update `docs/WORKLOG.md`**

Append a dated entry:

```markdown
## 2026-06-19: 박스스코어 기록실 연결형 개선

- [x] C 방향을 기존 박스스코어 계약 기반 기록실 연결형으로 확정
- [x] 매칭된 타자/투수 row와 핵심 카드에 `선수 기록 보기` 진입점 추가
- [x] 미매칭 선수 row는 기록만 표시하고 탭 진입점은 숨기도록 분리
- [x] placeholder-only 박스스코어 guard 유지 검증
```

- [ ] **Step 3: Update `CHANGELOG.md`**

Add a user-visible note under the latest unreleased/current section:

```markdown
- 경기 상세 박스스코어에서 매칭된 선수 기록을 바로 열 수 있도록 기록실 진입점을 강화했습니다.
```

## Task 5: Final Verification

**Files:**
- Verify all modified files.

- [ ] **Step 1: Format**

Run:

```bash
cd app && fvm dart format lib/features/game_detail/tabs/boxscore_tab.dart test/features/game_detail/boxscore_tab_test.dart
```

Expected: formatter completes with no syntax errors.

- [ ] **Step 2: Targeted tests**

Run:

```bash
cd app && fvm flutter test test/features/game_detail/boxscore_tab_test.dart --no-pub --reporter expanded
```

Expected: all boxscore tab tests pass.

- [ ] **Step 3: Targeted analyze**

Run:

```bash
cd app && fvm flutter analyze lib/features/game_detail/tabs/boxscore_tab.dart test/features/game_detail/boxscore_tab_test.dart --no-pub
```

Expected: no issues.

- [ ] **Step 4: Inspect diff**

Run:

```bash
git diff -- app/lib/features/game_detail/tabs/boxscore_tab.dart app/test/features/game_detail/boxscore_tab_test.dart docs/APP_SPEC.md docs/WORKLOG.md CHANGELOG.md
```

Expected: only C records-entry changes are present.

- [ ] **Step 5: Commit**

Run:

```bash
git add app/lib/features/game_detail/tabs/boxscore_tab.dart app/test/features/game_detail/boxscore_tab_test.dart docs/APP_SPEC.md docs/WORKLOG.md CHANGELOG.md docs/superpowers/plans/2026-06-19-boxscore-records-link.md
git commit -m "박스스코어 기록실 연결 개선"
```

Expected: commit succeeds on `codex/boxscore-records-link`.

## Self-Review

- Spec coverage: all requirements from `docs/superpowers/specs/2026-06-19-boxscore-records-link-design.md` map to Tasks 1-5.
- Placeholder scan: no open placeholder markers are present.
- Type consistency: plan uses existing `BoxscoreTab`, `GameBoxscoreData`, `TeamBoxscoreData`, `PlayerProfile`, `PlayerType`, and `GoRouter` APIs.
