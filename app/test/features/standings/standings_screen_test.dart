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
    expect(find.text('LG 트윈스'), findsOneWidget);

    await tester.tap(find.byType(DropdownButton<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('$previousSeason').last);
    await tester.pumpAndSettle();

    expect(requestedSeasons, contains(previousSeason));
    expect(find.text('KT 위즈'), findsOneWidget);
    expect(find.text('2연패'), findsOneWidget);
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
    expect(find.text('3연승'), findsOneWidget);
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
