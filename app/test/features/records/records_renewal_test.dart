import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kbo_fans/core/config/app_config.dart';
import 'package:kbo_fans/core/theme/app_theme.dart';
import 'package:kbo_fans/data/models/player.dart';
import 'package:kbo_fans/data/models/records_overview.dart';
import 'package:kbo_fans/data/models/team_records_bundle.dart';
import 'package:kbo_fans/data/models/team_stats.dart';
import 'package:kbo_fans/data/providers.dart';
import 'package:kbo_fans/features/records/player_comparison_sheet.dart';
import 'package:kbo_fans/features/records/records_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  AppConfig.initialize();

  testWidgets('팀 기록실의 일반 선택은 경기 상태색과 분리된 액션 블루를 사용한다', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          teamRecordsProvider.overrideWith((ref, key) async => _bundle(2024)),
        ],
        child: MaterialApp(
          theme: AppTheme.dark,
          home: const RecordsScreen(
            teamId: 'LG',
            initialSeason: 2024,
            followsCurrentSeason: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final tabBar = tester.widget<TabBar>(find.byType(TabBar));
    final tabIndicator = tabBar.indicator! as BoxDecoration;
    expect(
      tabIndicator.color,
      AppTheme.darkColors.accent.withValues(alpha: 0.16),
    );

    final filter = tester.widget<Container>(
      find.byKey(const ValueKey('records-filter-전체')),
    );
    final filterDecoration = filter.decoration! as BoxDecoration;
    expect(
      filterDecoration.border?.top.color,
      AppTheme.darkColors.accent.withValues(alpha: 0.72),
    );

    final sort = tester.widget<Container>(
      find.byKey(const ValueKey('records-sort-타율')),
    );
    final sortDecoration = sort.decoration! as BoxDecoration;
    expect(
      sortDecoration.border?.top.color,
      AppTheme.darkColors.accent.withValues(alpha: 0.62),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('내 팀 바로가기는 지연 리그 데이터 전후 위치와 시즌을 유지한다', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final overview = Completer<RecordsOverview>();
    final requests = <int>[];
    Uri? openedTeamUri;
    final router = GoRouter(
      initialLocation: '/records',
      routes: [
        GoRoute(
          path: '/records',
          builder: (_, _) => const RecordsScreen(
            initialSeason: 2024,
            followsCurrentSeason: false,
          ),
        ),
        GoRoute(
          path: '/records/team/:teamId',
          builder: (_, state) {
            openedTeamUri = state.uri;
            return Scaffold(body: Text('팀 진입 ${state.uri}'));
          },
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          myTeamProvider.overrideWith(_LgTeamNotifier.new),
          recordsOverviewProvider.overrideWith((ref, season) {
            requests.add(season);
            return overview.future;
          }),
        ],
        child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
      ),
    );
    await tester.pump();
    final shortcut = find.byKey(const ValueKey('records-my-team-shortcut'));
    expect(shortcut, findsOneWidget);
    final before = tester.getTopLeft(shortcut);
    expect(find.byKey(const ValueKey('records-team-LG')), findsNothing);
    overview.complete(_overview(2024));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(shortcut), before);
    expect(
      find.byKey(const ValueKey('records-briefing-panel')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('records-team-LG')), findsNothing);
    expect(requests, [2024]);
    await tester.tap(shortcut);
    await tester.pumpAndSettle();
    expect(openedTeamUri?.path, '/records/team/LG');
    expect(openedTeamUri?.queryParameters['season'], '2024');
    expect(openedTeamUri?.queryParameters.containsKey('seasonMode'), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('내 팀 바로가기가 있어도 팀 검색은 일치하는 내 팀을 결과에 포함한다', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          myTeamProvider.overrideWith(_LgTeamNotifier.new),
          recordsOverviewProvider.overrideWith(
            (ref, season) async => _overview(season),
          ),
        ],
        child: MaterialApp(theme: AppTheme.dark, home: const RecordsScreen()),
      ),
    );
    await tester.pumpAndSettle();
    final search = find.byType(TextField);
    await tester.scrollUntilVisible(
      search,
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(search, 'LG');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('records-team-LG')), findsOneWidget);
    expect(find.byKey(const ValueKey('records-team-OB')), findsNothing);
    await tester.enterText(search, '두산');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('records-team-LG')), findsNothing);
    expect(find.byKey(const ValueKey('records-team-OB')), findsOneWidget);
    await tester.enterText(search, '');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('records-team-LG')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('과거 시즌의 팀 진입과 복귀는 같은 시즌을 유지한다', (tester) async {
    final requested = <String>[];
    final router = GoRouter(
      initialLocation: '/records?season=2024',
      routes: [
        GoRoute(
          path: '/records',
          builder: (_, state) => RecordsScreen(
            initialSeason: int.tryParse(
              state.uri.queryParameters['season'] ?? '',
            ),
            followsCurrentSeason: false,
          ),
        ),
        GoRoute(
          path: '/records/team/:teamId',
          builder: (_, state) => RecordsScreen(
            teamId: state.pathParameters['teamId'],
            initialSeason: int.tryParse(
              state.uri.queryParameters['season'] ?? '',
            ),
            followsCurrentSeason: false,
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          recordsOverviewProvider.overrideWith(
            (ref, season) async => _overview(season),
          ),
          teamRecordsProvider.overrideWith((ref, key) async {
            requested.add(key);
            return _bundle(int.parse(key.split('|').last));
          }),
        ],
        child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    final team = find.byKey(const ValueKey('records-team-LG'));
    await tester.scrollUntilVisible(
      team,
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(team);
    await tester.pumpAndSettle();
    expect(
      router.routerDelegate.currentConfiguration.uri.queryParameters['season'],
      '2024',
    );
    expect(requested, ['LG|2024']);
    await tester.tap(find.byTooltip('뒤로'));
    await tester.pumpAndSettle();
    expect(
      router.routerDelegate.currentConfiguration.uri.toString(),
      '/records?season=2024',
    );
    await tester.scrollUntilVisible(
      find.byType(DropdownButton<int>),
      -500,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      tester
          .widget<DropdownButton<int>>(find.byType(DropdownButton<int>))
          .value,
      2024,
    );
  });

  testWidgets('선수 비교는 받은 팀 기록을 재사용하고 닫은 뒤 시즌을 새로 따른다', (tester) async {
    final requested = <String>[];
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          teamRecordsProvider.overrideWith((ref, key) async {
            requested.add(key);
            return _bundle(int.parse(key.split('|').last));
          }),
        ],
        child: MaterialApp(
          theme: AppTheme.dark,
          home: const RecordsScreen(
            teamId: 'LG',
            initialSeason: 2024,
            followsCurrentSeason: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('records-compare-players')));
    await tester.pumpAndSettle();
    expect(find.text('2024 · LG 트윈스 · 야수'), findsOneWidget);
    expect(find.byKey(const ValueKey('comparison-metric-AVG')), findsOneWidget);
    expect(find.byKey(const ValueKey('comparison-metric-ERA')), findsNothing);
    expect(requested, ['LG|2024']);
    await tester.tap(find.byTooltip('선수 비교 닫기'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButton<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2023').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('records-compare-players')));
    await tester.pumpAndSettle();
    expect(find.text('2023 · LG 트윈스 · 야수'), findsOneWidget);
    expect(requested, ['LG|2024', 'LG|2023']);
    await tester.tap(find.byTooltip('선수 비교 닫기'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(Tab, '투수'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('records-compare-players')),
          )
          .onPressed,
      isNull,
    );
    await tester.tap(find.widgetWithText(Tab, '야수'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('엔트리 제외').first);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('records-compare-players')), findsNothing);
    expect(requested, ['LG|2024', 'LG|2023']);
  });

  testWidgets('비교는 타팀과 투수를 제외하고 선택 초기화와 취소를 지원한다', (tester) async {
    await _pumpComparison(
      tester,
      players: [
        _player('a', '첫 타자'),
        _player('b', '둘째 타자'),
        _player('c', '셋째 타자'),
        _player('p', '투수', type: PlayerType.pitcher),
        _player('other', '다른팀', team: 'OB'),
      ],
    );
    expect(find.text('투수'), findsNothing);
    expect(find.text('다른팀'), findsNothing);
    expect(find.byKey(const ValueKey('comparison-metric-AVG')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('comparison-reset')));
    await tester.pumpAndSettle();
    expect(find.text('비교할 선수 두 명을 선택해 주세요.'), findsOneWidget);
    final dropdowns = find.byType(DropdownButtonFormField<String>);
    await tester.tap(dropdowns.first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('첫 타자').last);
    await tester.pumpAndSettle();
    await tester.tap(dropdowns.last);
    await tester.pumpAndSettle();
    // The second picker cannot select the same player as the first.
    expect(find.text('첫 타자'), findsOneWidget);
    await tester.tap(find.text('셋째 타자').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('comparison-metric-AVG')), findsOneWidget);
    await tester.tap(find.byTooltip('선수 비교 닫기'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('player-comparison-sheet')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('320px 큰 글자 비교와 미제공 값은 과장 없이 읽을 수 있다', (tester) async {
    tester.view.physicalSize = const Size(320, 844);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2.4;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await _pumpComparison(
      tester,
      players: [
        _player('a', '이름이긴첫번째선수', avg: null),
        _player('b', '이름이긴두번째선수'),
      ],
    );
    await tester.scrollUntilVisible(
      find.text('미제공 값이 있어 차이를 계산하지 않습니다'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('미제공 값이 있어 차이를 계산하지 않습니다'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  for (final scale in [1.0, 2.4]) {
    testWidgets('비교 선택기 $scale배 글자의 glyph가 실제 그리기 영역에 들어간다', (tester) async {
      tester.view.physicalSize = Size(scale == 1 ? 390 : 320, 844);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await _pumpComparison(
        tester,
        players: [_player('a', '오스틴'), _player('b', '송찬의')],
      );
      final fields = find.byType(DropdownButtonFormField<String>);
      for (final entry in [(fields.first, '오스틴'), (fields.last, '송찬의')]) {
        final selectedText = find.descendant(
          of: entry.$1,
          matching: find.text(entry.$2),
        );
        final paragraph = tester.renderObject<RenderParagraph>(selectedText);
        final boxes = paragraph.getBoxesForSelection(
          TextSelection(baseOffset: 0, extentOffset: entry.$2.length),
        );
        expect(boxes, isNotEmpty);
        final glyphBottom = boxes
            .map((box) => box.bottom)
            .reduce((a, b) => a > b ? a : b);
        expect(
          paragraph.size.height,
          greaterThanOrEqualTo(glyphBottom),
          reason: '선택된 선수 이름의 glyph를 dense field 높이로 잘라서는 안 됩니다.',
        );
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('OPS 미제공이어도 명시된 HR 원자료가 양쪽에 있으면 비교한다', (tester) async {
    await _pumpComparison(
      tester,
      players: [
        _player('a', '오스틴', ops: null, seasonStats: const ['G 122', 'HR 36']),
        _player('b', '송찬의', ops: null, seasonStats: const ['G 98', 'HR 10']),
      ],
    );
    final homeRuns = find.byKey(const ValueKey('comparison-metric-HR'));
    await tester.scrollUntilVisible(
      homeRuns,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.descendant(of: homeRuns, matching: find.text('36')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: homeRuns, matching: find.text('10')),
      findsOneWidget,
    );
    expect(find.text('차이 26 · 시즌 누적 기록'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('투수 누적 기록은 명시 SO/W/SV key와 실제 0을 사용한다', (tester) async {
    await _pumpComparison(
      tester,
      playerType: PlayerType.pitcher,
      players: [
        _player(
          'a',
          '첫 투수',
          type: PlayerType.pitcher,
          seasonStats: const ['SO 120', 'W 10', 'SV 0'],
        ),
        _player(
          'b',
          '둘째 투수',
          type: PlayerType.pitcher,
          seasonStats: const ['SO 88', 'W 4', 'SV 10'],
        ),
      ],
    );
    for (final key in ['SO', 'W', 'SV']) {
      final row = find.byKey(ValueKey('comparison-metric-$key'));
      await tester.scrollUntilVisible(
        row,
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(row, findsOneWidget);
    }
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('comparison-metric-SV')),
        matching: find.text('0'),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  for (final raw in [
    const ['HR 36', 'HR 35'],
    const ['HR 36개'],
    const ['홈런 36'],
  ]) {
    testWidgets('모호하거나 명시 key가 없는 누적값 $raw 은 비교에서 제외한다', (tester) async {
      await _pumpComparison(
        tester,
        players: [
          _player('a', '첫 타자', seasonStats: raw),
          _player('b', '둘째 타자', seasonStats: const ['HR 10']),
        ],
      );
      expect(find.byKey(const ValueKey('comparison-metric-HR')), findsNothing);
    });
  }
}

class _LgTeamNotifier extends MyTeamNotifier {
  @override
  String? build() => 'LG';
}

Future<void> _pumpComparison(
  WidgetTester tester, {
  required List<PlayerProfile> players,
  PlayerType playerType = PlayerType.hitter,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showPlayerComparison(
              context,
              players: players,
              teamId: 'LG',
              teamName: 'LG 트윈스',
              season: 2024,
              playerType: playerType,
            ),
            child: const Text('비교 열기'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('비교 열기'));
  await tester.pumpAndSettle();
}

PlayerProfile _player(
  String id,
  String name, {
  String team = 'LG',
  PlayerType type = PlayerType.hitter,
  double? avg = 0.3,
  double? ops = 0.8,
  List<String> seasonStats = const ['G 100', 'AB 300'],
}) => PlayerProfile(
  id: id,
  teamId: team,
  playerType: type,
  name: name,
  number: 1,
  position: '외야수',
  roleLabel: '야수',
  handedness: '',
  heightWeight: '',
  birthDate: '',
  status: PlayerAvailabilityStatus.available,
  rosterGroup: PlayerRosterGroup.entry,
  headlineStat: 'AVG .300',
  secondaryStat: 'OPS .800',
  seasonStats: seasonStats,
  highlights: const [],
  recentGames: const [],
  avg: avg,
  ops: ops,
);

TeamRecordsBundle _bundle(int season) => TeamRecordsBundle(
  players: [
    _player('a', '첫 타자'),
    _player('b', '둘째 타자'),
    _player('p', '투수', type: PlayerType.pitcher),
  ],
  teamStats: TeamStats(
    teamId: 'LG',
    season: season,
    hitting: const {},
    pitching: const {},
  ),
);

RecordsOverview _overview(int season) => RecordsOverview(
  season: season,
  avgLeaders: const [],
  hrLeaders: const [],
  opsLeaders: const [],
  opsPlusLeaders: const [],
  eraLeaders: const [],
  todayHitter: const FeaturedPlayerCard(label: ''),
  todayPitcher: const FeaturedPlayerCard(label: ''),
  monthHitter: const FeaturedPlayerCard(label: ''),
  monthPitcher: const FeaturedPlayerCard(label: ''),
);
