import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kbo_fans/core/theme/app_theme.dart';
import 'package:kbo_fans/data/models/player.dart';
import 'package:kbo_fans/data/providers.dart';
import 'package:kbo_fans/features/records/player_detail_screen.dart';

void main() {
  testWidgets('선수 상세 오류는 다시 시도해 프로필을 복구한다', (tester) async {
    var shouldFail = true;
    var loadCount = 0;
    final router = _playerRouter();
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          playerDetailProvider.overrideWith((ref, key) async {
            loadCount += 1;
            if (shouldFail) {
              throw Exception('network unavailable');
            }
            return _player;
          }),
        ],
        child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('선수 정보를 불러올 수 없습니다'), findsOneWidget);
    expect(find.text('다시 시도'), findsOneWidget);
    expect(find.text('기록실로'), findsOneWidget);

    shouldFail = false;
    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();

    expect(loadCount, greaterThan(1));
    expect(find.text('테스트 선수'), findsOneWidget);
    expect(find.text('선수 정보를 불러올 수 없습니다'), findsNothing);
  });

  testWidgets('선수 상세 오류는 기록실 루트로 복구한다', (tester) async {
    final router = _playerRouter();
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          playerDetailProvider.overrideWith((ref, key) async {
            throw Exception('network unavailable');
          }),
        ],
        child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('기록실로'));
    await tester.pumpAndSettle();

    expect(router.routerDelegate.currentConfiguration.uri.path, '/records');
    expect(find.text('기록실'), findsOneWidget);
  });
}

GoRouter _playerRouter() {
  return GoRouter(
    initialLocation: '/records/player/69102?season=2026',
    routes: [
      GoRoute(
        path: '/records',
        builder: (_, _) => const Scaffold(body: Text('기록실')),
      ),
      GoRoute(
        path: '/records/player/:playerId',
        builder: (_, state) => PlayerDetailScreen(
          playerId: state.pathParameters['playerId']!,
          season: int.parse(state.uri.queryParameters['season']!),
        ),
      ),
    ],
  );
}

const _player = PlayerProfile(
  id: '69102',
  teamId: 'LG',
  name: '테스트 선수',
  number: 1,
  position: '내야수',
  roleLabel: '타자',
  handedness: '우투우타',
  heightWeight: '180cm / 80kg',
  birthDate: '2000.01.01',
  status: PlayerAvailabilityStatus.available,
  rosterGroup: PlayerRosterGroup.entry,
  headlineStat: 'AVG 0.300',
  secondaryStat: 'OPS 0.800',
  seasonStats: [],
  highlights: [],
  recentGames: [],
);
