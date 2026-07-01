import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kbo_fans/core/config/app_config.dart';
import 'package:kbo_fans/core/theme/app_theme.dart';
import 'package:kbo_fans/data/models/records_overview.dart';
import 'package:kbo_fans/data/providers.dart';
import 'package:kbo_fans/features/records/leaderboard_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  AppConfig.initialize();

  testWidgets('리그 리더보드는 타자와 투수 탭에서 여러 지표를 전환한다', (tester) async {
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
    expect(requestedKeys, contains('2026|avg'));

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
    expect(requestedKeys, contains('2026|era'));

    await tester.tap(
      find.byKey(const ValueKey('leaderboard-metric-strikeouts')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 240));

    expect(find.text('올러'), findsOneWidget);
    expect(requestedKeys, contains('2026|strikeouts'));
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
    expect(find.textContaining('leaderboard:v3:wins:2026'), findsNothing);
    expect(find.textContaining('Bad state'), findsNothing);
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
