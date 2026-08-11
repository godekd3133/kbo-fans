import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kbo_fans/core/config/app_config.dart';
import 'package:kbo_fans/core/theme/app_theme.dart';
import 'package:kbo_fans/core/utils/kbo_time.dart';
import 'package:kbo_fans/data/models/records_overview.dart';
import 'package:kbo_fans/data/models/team_records_bundle.dart';
import 'package:kbo_fans/data/models/team_stats.dart';
import 'package:kbo_fans/data/providers.dart';
import 'package:kbo_fans/features/records/records_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  AppConfig.initialize();

  testWidgets('팀 기록실의 뒤로가기는 접근 가능한 이름을 제공한다', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          retry: (_, _) => null,
          overrides: [
            teamRecordsProvider.overrideWith(
              (ref, key) async => const TeamRecordsBundle(
                players: [],
                teamStats: TeamStats(
                  teamId: 'LG',
                  season: 2026,
                  hitting: {},
                  pitching: {},
                ),
              ),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.dark,
            home: const RecordsScreen(teamId: 'LG'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byTooltip('뒤로'), findsOneWidget);
      expect(find.bySemanticsLabel('뒤로'), findsOneWidget);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('현재 시즌을 보던 기록실은 KST 연도 전환을 즉시 따른다', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final currentSeason = kboCurrentSeason();
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          recordsOverviewProvider.overrideWith(
            (ref, season) async => _emptyOverview(season),
          ),
        ],
        child: MaterialApp(theme: AppTheme.dark, home: const RecordsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<DropdownButton<int>>(find.byType(DropdownButton<int>))
          .value,
      currentSeason,
    );
    expect(
      tester
          .widgetList<Icon>(find.byIcon(Icons.chevron_right))
          .every((icon) => icon.color == AppTheme.darkColors.textSupporting),
      isTrue,
    );

    final container = ProviderScope.containerOf(
      tester.element(find.byType(RecordsScreen)),
    );
    container
        .read(kboDateProvider.notifier)
        .refresh(instant: DateTime.utc(currentSeason, 12, 31, 15));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<DropdownButton<int>>(find.byType(DropdownButton<int>))
          .value,
      currentSeason + 1,
    );
  });

  testWidgets('320px 240% 기록실 리더보드는 44px 선택기와 읽을 수 있는 카드로 재배치된다', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 844);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2.4;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final currentSeason = kboCurrentSeason();
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          recordsOverviewProvider.overrideWith(
            (ref, season) async => _overviewWithLeader(season),
          ),
        ],
        child: MaterialApp(theme: AppTheme.dark, home: const RecordsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('records-leaderboard-hub')),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .getSize(
            find.byKey(const ValueKey('records-leaderboard-group-hitter')),
          )
          .height,
      greaterThanOrEqualTo(44),
    );
    expect(find.text('1위'), findsWidgets);
    expect(find.text('AVG 0.365'), findsWidgets);
    expect(find.text('KT 위즈'), findsWidgets);
    expect(find.text('$currentSeason'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}

RecordsOverview _emptyOverview(int season) => RecordsOverview(
  season: season,
  avgLeaders: const [],
  hrLeaders: const [],
  opsLeaders: const [],
  opsPlusLeaders: const [],
  eraLeaders: const [],
  todayHitter: const FeaturedPlayerCard(label: '오늘의 타자'),
  todayPitcher: const FeaturedPlayerCard(label: '오늘의 투수'),
  monthHitter: const FeaturedPlayerCard(label: '이달의 타자'),
  monthPitcher: const FeaturedPlayerCard(label: '이달의 투수'),
);

RecordsOverview _overviewWithLeader(int season) => RecordsOverview(
  season: season,
  avgLeaders: const [
    RecordLeader(
      rank: 1,
      playerId: '52605',
      playerType: 'hitter',
      metricKey: 'AVG',
      name: '최원준',
      teamId: 'KT',
      value: '0.365',
    ),
  ],
  hrLeaders: const [],
  opsLeaders: const [],
  opsPlusLeaders: const [],
  eraLeaders: const [],
  todayHitter: const FeaturedPlayerCard(label: '오늘의 타자'),
  todayPitcher: const FeaturedPlayerCard(label: '오늘의 투수'),
  monthHitter: const FeaturedPlayerCard(label: '이달의 타자'),
  monthPitcher: const FeaturedPlayerCard(label: '이달의 투수'),
);
