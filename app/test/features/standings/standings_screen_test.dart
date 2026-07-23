import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kbo_fans/core/utils/kbo_time.dart';
import 'package:kbo_fans/core/theme/app_theme.dart';
import 'package:kbo_fans/data/models/schedule.dart';
import 'package:kbo_fans/data/providers.dart';
import 'package:kbo_fans/features/standings/standings_screen.dart';

void main() {
  testWidgets('standings season dropdown reloads selected year', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final currentSeason = kboCurrentSeason();
    final previousSeason = currentSeason - 1;
    final requestedSeasons = <int>[];

    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          standingsProvider.overrideWith((ref, season) async {
            requestedSeasons.add(season);
            return [
              TeamStanding(
                rank: 1,
                teamId: season == previousSeason ? 'KT' : 'LG',
                teamName: season == previousSeason ? 'KT 위즈' : 'LG 트윈스',
                wins: season == previousSeason ? 76 : 25,
                losses: season == previousSeason ? 65 : 17,
                draws: season == previousSeason ? 3 : 1,
                pct: season == previousSeason ? '0.539' : '0.595',
                gb: '0',
                streak: season == previousSeason ? '2패' : '3승',
              ),
            ];
          }),
        ],
        child: MaterialApp(theme: AppTheme.dark, home: const StandingsScreen()),
      ),
    );

    await tester.pump();
    await tester.pump();

    expect(requestedSeasons, contains(currentSeason));
    expect(find.text('LG'), findsOneWidget);

    await tester.tap(find.byType(DropdownButton<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('$previousSeason').last);
    await tester.pumpAndSettle();

    expect(requestedSeasons, contains(previousSeason));
    expect(find.text('KT 위즈'), findsOneWidget);
    expect(find.text('2연패'), findsAtLeastNWidgets(1));
  });

  testWidgets('standings table shows team streak', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          standingsProvider.overrideWith((ref, season) async {
            return const [
              TeamStanding(
                rank: 1,
                teamId: 'LG',
                teamName: 'LG 트윈스',
                wins: 25,
                losses: 17,
                draws: 1,
                pct: '0.595',
                gb: '0',
                streak: '3승',
              ),
            ];
          }),
        ],
        child: MaterialApp(theme: AppTheme.dark, home: const StandingsScreen()),
      ),
    );

    await tester.pump();
    await tester.pump();

    expect(find.text('연속'), findsOneWidget);
    expect(find.text('1위 경쟁'), findsOneWidget);
    expect(find.text('연속 흐름'), findsOneWidget);
    expect(find.text('3연승'), findsAtLeastNWidgets(1));
  });

  testWidgets('standings table highlights my team row', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          myTeamProvider.overrideWith(() => _FixedMyTeamNotifier('LG')),
          standingsProvider.overrideWith((ref, season) async {
            return const [
              TeamStanding(
                rank: 1,
                teamId: 'KT',
                teamName: 'KT 위즈',
                wins: 26,
                losses: 17,
                draws: 1,
                pct: '0.605',
                gb: '0',
                streak: '1승',
              ),
              TeamStanding(
                rank: 2,
                teamId: 'LG',
                teamName: 'LG 트윈스',
                wins: 25,
                losses: 17,
                draws: 1,
                pct: '0.595',
                gb: '0.5',
                streak: '3승',
              ),
            ];
          }),
        ],
        child: MaterialApp(theme: AppTheme.dark, home: const StandingsScreen()),
      ),
    );

    await tester.pump();
    await tester.pump();

    expect(
      find.byKey(const ValueKey('standing-my-team-badge-LG')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('standing-my-team-badge-KT')),
      findsNothing,
    );
  });

  testWidgets('320px standings keeps every fixed column inside the viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          myTeamProvider.overrideWith(() => _FixedMyTeamNotifier('LG')),
          standingsProvider.overrideWith((ref, season) async {
            return const [
              TeamStanding(
                rank: 1,
                teamId: 'KT',
                teamName: 'KT 위즈',
                wins: 51,
                losses: 35,
                draws: 2,
                pct: '0.593',
                gb: '2',
                streak: '7승',
              ),
              TeamStanding(
                rank: 2,
                teamId: 'LG',
                teamName: 'LG 트윈스',
                wins: 52,
                losses: 38,
                draws: 0,
                pct: '0.578',
                gb: '3',
                streak: '6패',
              ),
            ];
          }),
        ],
        child: MaterialApp(theme: AppTheme.dark, home: const StandingsScreen()),
      ),
    );

    await tester.pump();
    await tester.pumpAndSettle();

    final myTeamRow = find.byKey(const ValueKey('standing-LG-2'));
    expect(myTeamRow, findsOneWidget);
    expect(find.text('LG'), findsOneWidget);
    expect(find.text('0.578'), findsOneWidget);
    expect(find.text('6연패'), findsAtLeastNWidgets(1));
    expect(
      find.byKey(const ValueKey('standing-my-team-badge-LG')),
      findsNothing,
      reason: '좁은 폭에서는 행 색·왼쪽 강조선으로 마이팀을 구분한다.',
    );
    expect(tester.getRect(myTeamRow).right, lessThanOrEqualTo(320));
    expect(tester.takeException(), isNull);
  });

  testWidgets('standings empty response shows artwork empty state', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          standingsProvider.overrideWith((ref, season) async {
            return const [];
          }),
        ],
        child: MaterialApp(theme: AppTheme.dark, home: const StandingsScreen()),
      ),
    );

    await tester.pump();
    await tester.pump();

    expect(find.text('순위 데이터가 아직 없습니다'), findsOneWidget);
    expect(find.text('다시 확인'), findsOneWidget);
    expect(find.text('연속'), findsNothing);
  });
}

class _FixedMyTeamNotifier extends MyTeamNotifier {
  _FixedMyTeamNotifier(this.teamId);

  final String? teamId;

  @override
  String? build() => teamId;
}
