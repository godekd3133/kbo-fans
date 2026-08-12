import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kbo_fans/core/config/app_config.dart';
import 'package:kbo_fans/core/theme/app_theme.dart';
import 'package:kbo_fans/core/utils/kbo_time.dart';
import 'package:kbo_fans/data/models/records_overview.dart';
import 'package:kbo_fans/data/providers.dart';
import 'package:kbo_fans/features/records/leaderboard_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  AppConfig.initialize();

  testWidgets('리그 리더보드는 타자와 투수 탭에서 여러 지표를 전환한다', (tester) async {
    final semantics = tester.ensureSemantics();
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final requestedKeys = <String>[];

    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          leaderboardProvider.overrideWith((ref, key) async {
            requestedKeys.add(key);
            final metric = key.split('|')[1];
            return switch (metric) {
              'era' => const [_ponceEraLeader],
              'strikeouts' => const [_ollerStrikeoutLeader],
              _ => const [_choiAvgLeader],
            };
          }),
        ],
        child: MaterialApp(
          theme: AppTheme.dark,
          home: const LeaderboardScreen(
            season: 2026,
            metric: LeaderboardMetric.avg,
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      find.byKey(const ValueKey('leaderboard-group-hitter')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('leaderboard-group-pitcher')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('leaderboard-metric-avg')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('leaderboard-metric-hr')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('leaderboard-metric-ops')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('leaderboard-metric-opsPlus')),
      findsOneWidget,
    );
    expect(find.text('최원준'), findsOneWidget);
    final averageLeader = find.byKey(const ValueKey('leader-avg-52605'));
    expect(
      tester
          .widget<Text>(
            find.descendant(of: averageLeader, matching: find.text('AVG')),
          )
          .style
          ?.color,
      AppTheme.darkColors.textSupporting,
    );
    expect(requestedKeys, contains('2026|avg'));
    expect(
      tester
          .getSemantics(find.byKey(const ValueKey('leaderboard-group-hitter')))
          .getSemanticsData()
          .flagsCollection
          .isSelected
          .toBoolOrNull(),
      isTrue,
    );
    expect(
      tester
          .getSemantics(find.byKey(const ValueKey('leaderboard-metric-avg')))
          .getSemanticsData()
          .flagsCollection
          .isSelected
          .toBoolOrNull(),
      isTrue,
    );

    await tester.tap(find.byKey(const ValueKey('leaderboard-metric-opsPlus')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 240));

    expect(find.text('리그 OPS 상대지수 리더보드'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('leaderboard-source-opsPlus')),
        matching: find.text('앱 계산'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('leaderboard-ops-relative-disclosure')),
      findsOneWidget,
    );
    expect(find.text(opsRelativeIndexDisclosure), findsOneWidget);
    expect(find.text('공식'), findsNothing);
    expect(requestedKeys, contains('2026|opsPlus'));

    await tester.tap(find.byKey(const ValueKey('leaderboard-group-pitcher')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 240));

    expect(
      find.byKey(const ValueKey('leaderboard-metric-era')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('leaderboard-metric-wins')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('leaderboard-metric-saves')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('leaderboard-metric-strikeouts')),
      findsOneWidget,
    );
    expect(find.text('폰세'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('leaderboard-ops-relative-disclosure')),
      findsNothing,
    );
    expect(requestedKeys, contains('2026|era'));
    expect(
      tester
          .getSemantics(find.byKey(const ValueKey('leaderboard-group-pitcher')))
          .getSemanticsData()
          .flagsCollection
          .isSelected
          .toBoolOrNull(),
      isTrue,
    );

    await tester.tap(
      find.byKey(const ValueKey('leaderboard-metric-strikeouts')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 240));

    expect(find.text('올러'), findsOneWidget);
    expect(requestedKeys, contains('2026|strikeouts'));
    semantics.dispose();
  });

  testWidgets('320px 240%에서도 리더보드 선택기는 44px 이상이고 정보가 잘리지 않는다', (tester) async {
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
          leaderboardProvider.overrideWith(
            (ref, key) async => const [_choiAvgLeader],
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.dark,
          home: const LeaderboardScreen(
            season: 2026,
            metric: LeaderboardMetric.avg,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 240));

    expect(
      tester
          .getSize(find.byKey(const ValueKey('leaderboard-group-hitter')))
          .height,
      greaterThanOrEqualTo(44),
    );
    expect(
      tester
          .getSize(find.byKey(const ValueKey('leaderboard-metric-avg')))
          .height,
      greaterThanOrEqualTo(44),
    );
    expect(find.text('리그 타율 리더보드'), findsOneWidget);
    expect(find.text('최원준'), findsOneWidget);
    expect(find.text('AVG 0.365'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('리그 리더보드는 내부 API cache 오류를 사용자용 문구로 숨긴다', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          leaderboardProvider.overrideWith((ref, key) async {
            throw StateError(
              'Invalid API cache payload for leaderboard:v3:wins:2026',
            );
          }),
        ],
        child: MaterialApp(
          theme: AppTheme.dark,
          home: const LeaderboardScreen(
            season: 2026,
            metric: LeaderboardMetric.wins,
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('데이터를 불러오지 못했습니다. 잠시 후 다시 시도해주세요.'), findsOneWidget);
    expect(
      tester
          .widget<Text>(find.text('데이터를 불러오지 못했습니다. 잠시 후 다시 시도해주세요.'))
          .style
          ?.color,
      AppTheme.darkColors.textSupporting,
    );
    expect(find.textContaining('leaderboard:v3:wins:2026'), findsNothing);
    expect(find.textContaining('Bad state'), findsNothing);
  });

  testWidgets('리더보드 오류 상태에서 다시 시도하면 데이터를 복구한다', (tester) async {
    var attempts = 0;
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          leaderboardProvider.overrideWith((ref, key) async {
            attempts += 1;
            if (attempts == 1) {
              throw StateError('temporary failure');
            }
            return const [_choiAvgLeader];
          }),
        ],
        child: MaterialApp(
          theme: AppTheme.dark,
          home: const LeaderboardScreen(
            season: 2026,
            metric: LeaderboardMetric.wins,
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('다시 시도'), findsOneWidget);
    expect(find.text('최원준'), findsNothing);

    await tester.tap(find.text('다시 시도'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('최원준'), findsOneWidget);
    expect(attempts, 2);
  });

  testWidgets('현재 시즌에서 연 리더보드는 KST 1월 1일에 다음 시즌을 요청한다', (tester) async {
    final currentSeason = kboCurrentSeason();
    final requestedKeys = <String>[];

    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          leaderboardProvider.overrideWith((ref, key) async {
            requestedKeys.add(key);
            return const [_choiAvgLeader];
          }),
        ],
        child: MaterialApp(
          theme: AppTheme.dark,
          home: LeaderboardScreen(
            season: currentSeason,
            metric: LeaderboardMetric.avg,
            followsCurrentSeason: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(LeaderboardScreen)),
    );
    container
        .read(kboDateProvider.notifier)
        .refresh(instant: DateTime.utc(currentSeason, 12, 31, 15));
    await tester.pumpAndSettle();

    expect(requestedKeys, contains('${currentSeason + 1}|avg'));
    expect(find.text('${currentSeason + 1} 시즌 · 타자 지표'), findsOneWidget);
  });
}

const _choiAvgLeader = RecordLeader(
  rank: 1,
  playerId: '52605',
  playerType: 'hitter',
  metricKey: 'AVG',
  name: '최원준',
  teamId: 'KT',
  value: '0.365',
);

const _ponceEraLeader = RecordLeader(
  rank: 1,
  playerId: '65764',
  playerType: 'pitcher',
  metricKey: 'ERA',
  name: '폰세',
  teamId: 'HH',
  value: '2.51',
);

const _ollerStrikeoutLeader = RecordLeader(
  rank: 1,
  playerId: '55633',
  playerType: 'pitcher',
  metricKey: 'SO',
  name: '올러',
  teamId: 'HT',
  value: '108',
);
