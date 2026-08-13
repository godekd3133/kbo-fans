import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kbo_fans/core/config/app_config.dart';
import 'package:kbo_fans/core/theme/app_theme.dart';
import 'package:kbo_fans/data/models/records_overview.dart';
import 'package:kbo_fans/data/models/schedule.dart';
import 'package:kbo_fans/data/providers.dart';
import 'package:kbo_fans/features/records/records_screen.dart';
import 'package:kbo_fans/features/standings/standings_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  AppConfig.initialize();

  testWidgets('모바일 기록 영역은 큰 글자에서도 순위표와 선수 기록을 오갈 수 있다', (tester) async {
    final semantics = tester.ensureSemantics();
    final router = GoRouter(
      initialLocation: '/records',
      routes: [
        GoRoute(
          path: '/records',
          builder: (context, state) => const RecordsScreen(),
        ),
        GoRoute(
          path: '/standings',
          builder: (context, state) => const StandingsScreen(),
        ),
      ],
    );
    addTearDown(router.dispose);

    try {
      tester.view.physicalSize = const Size(320, 844);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2.4;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await tester.pumpWidget(
        ProviderScope(
          retry: (_, _) => null,
          overrides: [
            recordsOverviewProvider.overrideWith(
              (ref, season) async => _emptyOverview(season),
            ),
            standingsProvider.overrideWith(
              (ref, season) async => const [
                TeamStanding(
                  rank: 1,
                  teamId: 'LG',
                  teamName: 'LG 트윈스',
                  wins: 52,
                  losses: 38,
                  draws: 0,
                  pct: '0.578',
                  gb: '0',
                  streak: '6승',
                ),
              ],
            ),
          ],
          child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      final recordsTab = find.byKey(const ValueKey('records-area-tab-records'));
      final standingsTab = find.byKey(
        const ValueKey('records-area-tab-standings'),
      );
      expect(recordsTab, findsOneWidget);
      expect(standingsTab, findsOneWidget);
      expect(tester.getSize(recordsTab).height, greaterThanOrEqualTo(44));
      expect(tester.getSize(standingsTab).height, greaterThanOrEqualTo(44));
      expect(
        tester.getSemantics(recordsTab).flagsCollection.isSelected,
        Tristate.isTrue,
      );
      expect(
        tester.getSemantics(standingsTab).flagsCollection.isSelected,
        Tristate.isFalse,
      );
      expect(tester.takeException(), isNull);

      await tester.tap(standingsTab);
      await tester.pumpAndSettle();

      expect(find.byType(StandingsScreen), findsOneWidget);
      expect(
        tester
            .getSemantics(
              find.byKey(const ValueKey('records-area-tab-standings')),
            )
            .flagsCollection
            .isSelected,
        Tristate.isTrue,
      );
      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(const ValueKey('records-area-tab-records')));
      await tester.pumpAndSettle();

      expect(find.byType(RecordsScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('와이드 기록 화면은 기존 전용 네비게이션을 유지한다', (tester) async {
    tester.view.physicalSize = const Size(700, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

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

    expect(find.byKey(const ValueKey('records-area-switcher')), findsNothing);
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
