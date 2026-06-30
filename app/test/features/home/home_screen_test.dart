import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kbo_fans/core/config/app_config.dart';
import 'package:kbo_fans/data/models/game.dart';
import 'package:kbo_fans/data/models/home_aggregate.dart';
import 'package:kbo_fans/data/models/player.dart';
import 'package:kbo_fans/data/models/records_overview.dart';
import 'package:kbo_fans/data/models/relay.dart';
import 'package:kbo_fans/data/models/schedule.dart';
import 'package:kbo_fans/data/providers.dart';
import 'package:kbo_fans/features/home/home_screen.dart';
import 'package:kbo_fans/services/live_activity_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('경기 상세 진입 전 relay 선수 사진 prefetch 후보를 계산한다', () {
    const relayData = RelayData(
      currentAtBat: CurrentAtBat(
        batterName: '김도영',
        batterImageUrl: 'https://img.example.com/doyoung.jpg',
        batterNumber: 5,
        batterHand: '우타',
        pitcherName: '곽빈',
        pitcherNumber: 47,
        pitcherHand: '우투',
        pitchCount: 12,
        balls: 1,
        strikes: 0,
        outs: 1,
      ),
      relayItems: [
        RelayItem(
          seqNo: 11,
          inning: 9,
          half: 'bottom',
          event: 'OUT',
          text: '이유찬: 좌익수 플라이 아웃',
        ),
        RelayItem(
          seqNo: 10,
          inning: 9,
          half: 'top',
          event: 'HIT',
          text: '김도영: 우전 안타',
        ),
      ],
    );

    final urls = relayPlayerImagePrefetchUrlsForTesting(
      relayData: relayData,
      teamPlayers: [
        _playerProfile(name: '곽빈', id: '67263'),
        _playerProfile(name: '이유찬', id: '66244'),
      ],
      season: 2026,
    );

    expect(urls, [
      'https://img.example.com/doyoung.jpg',
      kboPlayerImageUrl(season: 2026, playerId: '67263'),
      kboPlayerImageUrl(season: 2026, playerId: '66244'),
    ]);
  });

  testWidgets('defers home aggregate provider until after scoreboard paint', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    _ensureAppConfigInitialized();
    SharedPreferences.setMockInitialValues({});
    var aggregateCalls = 0;

    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          scoreboardProvider.overrideWith((ref, date) async {
            return const <Game>[];
          }),
          homeAggregateProvider.overrideWith((ref, key) async {
            aggregateCalls++;
            return HomeAggregate(
              date: key.split('|').first,
              myTeam: null,
              myTeamBrief: null,
              kboBrief: null,
              quickItems: const [],
            );
          }),
        ],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );

    await tester.pump();

    expect(find.text('홈 첫 화면을 먼저 띄우는 중입니다.'), findsOneWidget);
    expect(find.text('일정 보기'), findsAtLeastNWidgets(1));
    expect(find.text('순위'), findsOneWidget);
    expect(aggregateCalls, 0);

    await tester.pump();

    expect(aggregateCalls, 1);
  });

  testWidgets('keeps the last home scoreboard when resume refresh fails', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    _ensureAppConfigInitialized();
    SharedPreferences.setMockInitialValues({});
    final game = _scheduledGame(
      gameId: '20260619AABB0',
      awayTeamId: 'AA',
      awayShortName: 'A',
      homeTeamId: 'BB',
      homeShortName: 'B',
      stadium: '잠실',
    );
    var scoreboardCalls = 0;
    final container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        scoreboardProvider.overrideWith((ref, date) async {
          scoreboardCalls++;
          if (scoreboardCalls > 1) {
            throw Exception('network unavailable after resume');
          }
          return [game];
        }),
        homeAggregateProvider.overrideWith((ref, key) async {
          return HomeAggregate(
            date: key.split('|').first,
            myTeam: null,
            myTeamBrief: null,
            kboBrief: null,
            quickItems: const [],
          );
        }),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    final gameRowFinder = find.byKey(
      ValueKey('home-today-game-${game.gameId}'),
    );
    expect(gameRowFinder, findsOneWidget);
    expect(find.text('다시 시도'), findsNothing);

    container.invalidate(scoreboardProvider(_todayKey()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(gameRowFinder, findsOneWidget);
    expect(find.text('다시 시도'), findsNothing);
  });

  testWidgets('auto follows a live my team game on home', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({'myTeam': 'XX'});
    _ensureAppConfigInitialized();
    final liveMyTeamGame = _liveGame(
      gameId: '20260611XXYY0',
      awayTeamId: 'XX',
      homeTeamId: 'YY',
    );

    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          myTeamProvider.overrideWith(() => _FixedMyTeamNotifier('XX')),
          scoreboardProvider.overrideWith((ref, date) async {
            return [liveMyTeamGame];
          }),
          homeAggregateProvider.overrideWith((ref, key) async {
            return HomeAggregate(
              date: key.split('|').first,
              myTeam: 'XX',
              myTeamBrief: null,
              kboBrief: null,
              quickItems: const [],
            );
          }),
        ],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );

    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();

    expect(
      await LiveActivityService.instance.followedGameId(),
      liveMyTeamGame.gameId,
    );
    expect(
      find.byKey(ValueKey('home-today-game-${liveMyTeamGame.gameId}')),
      findsOneWidget,
    );
  });

  testWidgets(
    'shows live my-team relay card above today games and opens relay',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      SharedPreferences.setMockInitialValues({'myTeam': 'LG'});
      _ensureAppConfigInitialized();
      final router = _homeInteractionRouter();
      final liveMyTeamGame = _liveGame(
        gameId: '20260611SSLG0',
        awayTeamId: 'SS',
        homeTeamId: 'LG',
      );

      await tester.pumpWidget(
        _homeInteractionScope(
          scoreboardGames: [liveMyTeamGame],
          child: ProviderScope(
            retry: (_, _) => null,
            overrides: [
              gameProvider.overrideWith((ref, gameId) async => liveMyTeamGame),
              relayDataProvider.overrideWith(
                (ref, gameId) async =>
                    const RelayData(currentAtBat: null, relayItems: []),
              ),
            ],
            child: MaterialApp.router(routerConfig: router),
          ),
        ),
      );

      await tester.pump();
      await tester.pump();
      await tester.pumpAndSettle();

      final liveCard = find.byKey(const ValueKey('home-live-my-team-game'));
      final todayHeader = find.byKey(const ValueKey('home-today-games-header'));
      expect(liveCard, findsOneWidget);
      expect(find.text('내 경기 진행 중'), findsOneWidget);
      expect(find.text('문자중계 보기'), findsOneWidget);
      expect(
        tester.getTopLeft(liveCard).dy,
        lessThan(tester.getTopLeft(todayHeader).dy),
      );

      await tester.tap(liveCard);
      await tester.pump();
      await tester.pumpAndSettle();

      expect(
        find.text('game-detail-${liveMyTeamGame.gameId}-tab-relay'),
        findsOneWidget,
      );
      expect(find.text('game-detail-focus-relay'), findsOneWidget);
    },
  );

  testWidgets('deduplicates today games and keeps my-team row visible', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({'myTeam': 'LG'});
    _ensureAppConfigInitialized();
    final myTeamGame = _scheduledGame(
      gameId: '20260611HTLG0',
      awayTeamId: 'HT',
      awayShortName: 'KIA',
      homeTeamId: 'LG',
      homeShortName: 'LG',
      stadium: '잠실',
    );
    final otherGame = _scheduledGame(
      gameId: '20260611NCOB0',
      awayTeamId: 'NC',
      awayShortName: 'NC',
      homeTeamId: 'OB',
      homeShortName: '두산',
      stadium: '창원',
    );

    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          myTeamProvider.overrideWith(() => _FixedMyTeamNotifier('LG')),
          scoreboardProvider.overrideWith((ref, date) async {
            return [myTeamGame, otherGame, otherGame];
          }),
          homeAggregateProvider.overrideWith((ref, key) async {
            return HomeAggregate(
              date: key.split('|').first,
              myTeam: 'LG',
              myTeamBrief: null,
              kboBrief: null,
              quickItems: const [],
            );
          }),
        ],
        child: MaterialApp(
          builder: (context, child) {
            final data = MediaQuery.of(
              context,
            ).copyWith(disableAnimations: true);
            return MediaQuery(data: data, child: child!);
          },
          home: const HomeScreen(),
        ),
      ),
    );

    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();

    expect(
      find.byKey(ValueKey('home-today-game-${myTeamGame.gameId}')),
      findsOneWidget,
    );
    expect(
      find.byKey(ValueKey('home-today-game-${otherGame.gameId}')),
      findsOneWidget,
    );
  });

  testWidgets(
    'home shows all today games and standings without view-all CTAs',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      SharedPreferences.setMockInitialValues({'myTeam': 'LG'});
      _ensureAppConfigInitialized();
      final router = _homeInteractionRouter();
      final games = [
        _scheduledGame(
          gameId: '20260619SSLG0',
          awayTeamId: 'SS',
          awayShortName: '삼성',
          homeTeamId: 'LG',
          homeShortName: 'LG',
          stadium: '잠실',
        ),
        _scheduledGame(
          gameId: '20260619HTOB0',
          awayTeamId: 'HT',
          awayShortName: 'KIA',
          homeTeamId: 'OB',
          homeShortName: '두산',
          stadium: '광주',
        ),
        _scheduledGame(
          gameId: '20260619NCKT0',
          awayTeamId: 'NC',
          awayShortName: 'NC',
          homeTeamId: 'KT',
          homeShortName: 'KT',
          stadium: '창원',
        ),
        _scheduledGame(
          gameId: '20260619WOLT0',
          awayTeamId: 'WO',
          awayShortName: '키움',
          homeTeamId: 'LT',
          homeShortName: '롯데',
          stadium: '고척',
        ),
        _scheduledGame(
          gameId: '20260619HHSK0',
          awayTeamId: 'HH',
          awayShortName: '한화',
          homeTeamId: 'SK',
          homeShortName: 'SSG',
          stadium: '대전',
        ),
      ];
      final standings = _leagueStandings();

      await tester.pumpWidget(
        _homeInteractionScope(
          child: MaterialApp.router(routerConfig: router),
          scoreboardGames: games,
          standingsPreview: standings,
        ),
      );

      await tester.pump();
      await tester.pump();
      await tester.pumpAndSettle();

      final todayHeader = find.byKey(const ValueKey('home-today-games-header'));
      expect(
        find.descendant(
          of: todayHeader,
          matching: find.widgetWithText(TextButton, '전체 보기'),
        ),
        findsNothing,
      );
      for (final game in games) {
        expect(
          find.byKey(ValueKey('home-today-game-${game.gameId}')),
          findsOneWidget,
        );
      }

      final standingsHeader = find.byKey(
        const ValueKey('home-standings-header'),
      );
      expect(
        find.descendant(
          of: standingsHeader,
          matching: find.widgetWithText(TextButton, '전체 보기'),
        ),
        findsNothing,
      );
      for (final standing in standings) {
        expect(
          find.byKey(ValueKey('home-standings-row-${standing.teamId}')),
          findsOneWidget,
        );
      }
    },
  );

  testWidgets('recent flow row opens team records with press interaction', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({'myTeam': 'LG'});
    _ensureAppConfigInitialized();
    final router = _homeInteractionRouter();

    await tester.pumpWidget(
      _homeInteractionScope(child: MaterialApp.router(routerConfig: router)),
    );

    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();

    await tester.tap(find.text('4연승'));
    await tester.pumpAndSettle();

    expect(find.text('team-record-LG'), findsOneWidget);
  });

  testWidgets('recent flow renders every standings team below standings', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({'myTeam': 'LG'});
    _ensureAppConfigInitialized();
    final router = _homeInteractionRouter();

    await tester.pumpWidget(
      _homeInteractionScope(child: MaterialApp.router(routerConfig: router)),
    );

    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('home-recent-flow-row-HT')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('home-recent-flow-row-LG')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('home-recent-flow-row-SS')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('home-recent-flow-row-KT')),
      findsOneWidget,
    );
  });

  testWidgets('standings row opens standings overview like View All', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({'myTeam': 'LG'});
    _ensureAppConfigInitialized();
    final router = _homeInteractionRouter();

    await tester.pumpWidget(
      _homeInteractionScope(child: MaterialApp.router(routerConfig: router)),
    );

    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();

    final standingsRow = find.byKey(const ValueKey('home-standings-row-HT'));
    await tester.ensureVisible(standingsRow);
    await tester.tap(standingsRow);
    await tester.pumpAndSettle();

    expect(find.text('standings'), findsOneWidget);
  });

  testWidgets('home notification header opens notification inbox', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({'myTeam': 'LG'});
    _ensureAppConfigInitialized();
    final router = _homeInteractionRouter();

    await tester.pumpWidget(
      _homeInteractionScope(child: MaterialApp.router(routerConfig: router)),
    );

    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('알림 설정'));
    await tester.pumpAndSettle();

    expect(find.text('notifications'), findsOneWidget);
  });

  testWidgets('KBO brief record item renders real player image URL', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({'myTeam': 'LG'});
    _ensureAppConfigInitialized();
    final router = _homeInteractionRouter();
    const imageUrl =
        'https://6ptotvmi5753.edge.naverncp.com/KBO_IMAGE/person/middle/2026/52605.jpg';

    await tester.pumpWidget(
      _homeInteractionScope(
        child: MaterialApp.router(routerConfig: router),
        kboBrief: const HomeKboBrief(
          title: '오늘의 KBO 소식',
          subtitle: '실제 기록 신호',
          items: [
            HomeKboBriefItem(
              type: 'record_radar',
              eyebrow: '기록 레이더',
              title: '김도영 13홈런',
              subtitle: 'KIA 타이거즈 · 시즌 홈런 1위',
              route: '/records/player/52605?season=2026',
              teamIds: ['HT'],
              imageUrl: imageUrl,
              fallbackLabel: '김도영',
            ),
          ],
        ),
      ),
    );

    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();

    expect(
      find.byWidgetPredicate(
        (widget) => widget is CachedNetworkImage && widget.imageUrl == imageUrl,
      ),
      findsOneWidget,
    );
  });

  testWidgets('home insight and quick cards keep long copy visible', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({'myTeam': 'LG'});
    _ensureAppConfigInitialized();
    final router = _homeInteractionRouter();
    final standings = [
      _standing(
        rank: 1,
        teamId: 'LG',
        teamName: 'LG 트윈스',
        wins: 42,
        losses: 35,
        draws: 1,
        pct: '.545',
        gb: '-',
        streak: 'W2',
      ),
      _standing(
        rank: 5,
        teamId: 'OB',
        teamName: '두산 베어스',
        wins: 38,
        losses: 38,
        draws: 2,
        pct: '.500',
        gb: '9.5',
        streak: 'L1',
      ),
    ];

    await tester.pumpWidget(
      _homeInteractionScope(
        child: MaterialApp.router(routerConfig: router),
        standingsPreview: standings,
        kboBrief: const HomeKboBrief(
          title: '오늘의 KBO 소식',
          subtitle: '지금 볼 장면 3개',
          items: [
            HomeKboBriefItem(
              type: 'standings',
              eyebrow: '선두권',
              title: '1위 LG 트윈스',
              subtitle: '삼성 라이온즈와 2.5G차 · 선두권 흐름 확인',
              route: '/standings',
              teamIds: ['LG', 'SS'],
            ),
            HomeKboBriefItem(
              type: 'record_radar',
              eyebrow: '기록 레이더',
              title: '오스틴 24홈런',
              subtitle: 'LG 트윈스 · 시즌 홈런 선두권 경쟁 중',
              route: '/records',
              teamIds: ['LG'],
            ),
            HomeKboBriefItem(
              type: 'big_match',
              eyebrow: '오늘 일정',
              title: '롯데 자이언츠 vs 두산 베어스',
              subtitle: '18:30 · 잠실 · 오늘 5경기 예정',
              route: '/game/20260630LTOB0',
              teamIds: ['LT', 'OB'],
            ),
          ],
        ),
        quickItems: const [
          HomeQuickItem(
            eyebrow: '마이팀 순위',
            title: '5위 · 두산 베어스',
            subtitle: '38승 38패 2무 · 9.5G차',
            route: '/standings',
            teamId: 'OB',
            fallbackLabel: '두산 베어스',
          ),
        ],
      ),
    );

    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('오늘의 KBO 소식'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('kbo-brief-team-logo-standings-LG')),
      findsAtLeastNWidgets(1),
    );
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(find.text('지금 보면 좋은 정보'));
    await tester.pumpAndSettle();

    expect(find.text('5위 · 두산 베어스'), findsOneWidget);
    expect(find.text('38승 38패 2무 · 9.5G차'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('KBO brief hides remaining-game footer and stale item', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({'myTeam': 'LG'});
    _ensureAppConfigInitialized();
    final router = _homeInteractionRouter();

    await tester.pumpWidget(
      _homeInteractionScope(
        child: MaterialApp.router(routerConfig: router),
        kboBrief: const HomeKboBrief(
          title: '오늘의 KBO 소식',
          subtitle: '지금 볼 장면 2개',
          items: [
            HomeKboBriefItem(
              type: 'big_match',
              eyebrow: '오늘 일정',
              title: '삼성 vs LG',
              subtitle: '18:30 · 잠실 · 오늘 2경기 예정',
              route: '/game/20260619SSLG0',
            ),
            HomeKboBriefItem(
              type: 'schedule_remaining',
              eyebrow: '남은 경기',
              title: 'SSG vs 두산 외 1경기',
              subtitle: '18:30 시작 · 중계 바로가기',
              route: '/schedule',
            ),
          ],
        ),
      ),
    );

    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('오늘의 KBO 소식'));
    await tester.pumpAndSettle();

    expect(find.text('오늘의 KBO 소식'), findsOneWidget);
    expect(find.text('삼성 vs LG'), findsAtLeastNWidgets(1));
    expect(find.text('오늘 남은 경기 2'), findsNothing);
    expect(find.text('남은 경기'), findsNothing);
    expect(find.text('SSG vs 두산 외 1경기'), findsNothing);
    expect(find.text('중계 바로가기'), findsNothing);
  });

  testWidgets('KBO brief scheduled feature does not render as LIVE', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({'myTeam': 'LG'});
    _ensureAppConfigInitialized();
    final router = _homeInteractionRouter();

    await tester.pumpWidget(
      _homeInteractionScope(
        child: MaterialApp.router(routerConfig: router),
        kboBrief: const HomeKboBrief(
          title: '오늘의 KBO 소식',
          subtitle: '지금 볼 장면 1개',
          items: [
            HomeKboBriefItem(
              type: 'big_match',
              eyebrow: '오늘 일정',
              title: '롯데 vs 두산',
              subtitle: '18:30 · 잠실 · 오늘 5경기 예정',
              route: '/game/20260630LTOB0',
              gameId: '20260630LTOB0',
              teamIds: ['LT', 'OB'],
            ),
          ],
        ),
      ),
    );

    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('오늘의 KBO 소식'));
    await tester.pumpAndSettle();

    expect(find.text('롯데 vs 두산'), findsAtLeastNWidgets(1));
    expect(find.text('예정'), findsAtLeastNWidgets(1));
    expect(find.text('LIVE'), findsNothing);
    expect(find.text('B'), findsNothing);
    expect(find.text('S'), findsNothing);
    expect(find.text('O'), findsNothing);
  });

  testWidgets('home broad insight CTAs open news brief instead of records', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({'myTeam': 'LG'});
    _ensureAppConfigInitialized();
    final router = _homeInteractionRouter();

    await tester.pumpWidget(
      _homeInteractionScope(
        child: MaterialApp.router(routerConfig: router),
        kboBrief: const HomeKboBrief(
          title: 'KBO 소식',
          subtitle: '2경기 예정',
          items: [
            HomeKboBriefItem(
              type: 'big_match',
              eyebrow: '오늘 일정',
              title: '삼성 vs LG',
              subtitle: '18:30 · 잠실 · 오늘 2경기 예정',
              route: '/game/20260619SSLG0',
            ),
            HomeKboBriefItem(
              type: 'standings',
              eyebrow: '선두권',
              title: 'KIA 1위',
              subtitle: 'LG와 2.0G차',
              route: '/standings',
            ),
          ],
        ),
        quickItems: const [
          HomeQuickItem(
            eyebrow: '홈런왕',
            title: '김도영 13개',
            subtitle: 'KIA · 시즌 홈런 1위',
            route: '/records/player/52605?season=2026',
          ),
        ],
      ),
    );

    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('인사이트'));
    await tester.pumpAndSettle();

    final insightHeader = find.ancestor(
      of: find.text('인사이트'),
      matching: find.byType(Row),
    );
    await tester.tap(
      find.descendant(
        of: insightHeader,
        matching: find.widgetWithText(TextButton, '전체 보기'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('news'), findsOneWidget);

    router.go('/home');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('지금 보면 좋은 정보'));
    await tester.pumpAndSettle();

    final quickHeader = find.ancestor(
      of: find.text('지금 보면 좋은 정보'),
      matching: find.byType(Row),
    );
    await tester.tap(
      find.descendant(
        of: quickHeader,
        matching: find.widgetWithText(TextButton, '더보기'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('news'), findsOneWidget);
  });

  test('진행 중인 경기 상세 route는 기본으로 중계 탭을 지정한다', () {
    final liveGame = _liveGame(
      gameId: '20260611XXYY0',
      awayTeamId: 'XX',
      homeTeamId: 'YY',
    );

    final uri = Uri.parse(gameDetailLocationFor(liveGame));

    expect(uri.path, '/game/${liveGame.gameId}');
    expect(uri.queryParameters['tab'], 'relay');
  });

  test('홈 경기 박스 route는 진행 중 경기만 중계 탭을 지정한다', () {
    final liveUri = Uri.parse(
      gameDetailLocationForGameId(
        gameId: '20260611XXYY0',
        status: GameStatus.live,
      ),
    );
    final scheduledUri = Uri.parse(
      gameDetailLocationForGameId(
        gameId: '20260612XXYY0',
        status: GameStatus.scheduled,
      ),
    );

    expect(liveUri.path, '/game/20260611XXYY0');
    expect(liveUri.queryParameters['tab'], 'relay');
    expect(scheduledUri.path, '/game/20260612XXYY0');
    expect(scheduledUri.queryParameters.containsKey('tab'), isFalse);
  });

  test('마이팀 중계 보기 route는 중계 본문 focus 신호를 포함한다', () {
    final liveMyTeamGame = _liveGame(
      gameId: '20260611XXYY0',
      awayTeamId: 'XX',
      homeTeamId: 'YY',
    );

    final uri = Uri.parse(
      gameDetailLocationFor(liveMyTeamGame, tab: 'relay', focusRelay: true),
    );

    expect(uri.path, '/game/${liveMyTeamGame.gameId}');
    expect(uri.queryParameters['tab'], 'relay');
    expect(uri.queryParameters['focus'], 'relay');
  });

  testWidgets('홈 경기 상세 진입은 최신 상세 데이터 갱신 후 이동한다', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({'myTeam': 'LG'});
    _ensureAppConfigInitialized();
    final router = _homeInteractionRouter();
    final liveGame = _liveGame(
      gameId: '20260611SSLG0',
      awayTeamId: 'SS',
      homeTeamId: 'LG',
    );
    final freshDetail = Game(
      gameId: liveGame.gameId,
      status: GameStatus.live,
      inning: '8회초',
      away: const TeamScore(
        teamId: 'SS',
        teamName: 'SS',
        shortName: 'SS',
        score: 3,
        innings: [],
      ),
      home: const TeamScore(
        teamId: 'LG',
        teamName: 'LG',
        shortName: 'LG',
        score: 4,
        innings: [],
      ),
      stadium: '잠실',
      startTime: '18:30',
    );
    final detailCompleter = Completer<Game?>();
    final relayCompleter = Completer<RelayData>();
    var detailFetches = 0;
    var relayFetches = 0;

    await tester.pumpWidget(
      _homeInteractionScope(
        scoreboardGames: [liveGame],
        child: ProviderScope(
          retry: (_, _) => null,
          overrides: [
            gameProvider.overrideWith((ref, gameId) async {
              detailFetches++;
              return detailCompleter.future;
            }),
            relayDataProvider.overrideWith((ref, gameId) async {
              relayFetches++;
              return relayCompleter.future;
            }),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      ),
    );

    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();

    final row = find.byKey(ValueKey('home-today-game-${liveGame.gameId}'));
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    await tester.tap(row);
    await tester.pump();

    expect(router.routerDelegate.currentConfiguration.uri.path, '/home');
    expect(
      find.byKey(const ValueKey('home-game-detail-loading')),
      findsOneWidget,
    );
    expect(find.text('game-detail-${liveGame.gameId}-tab-relay'), findsNothing);
    expect(detailFetches, 1);
    expect(relayFetches, 1);

    detailCompleter.complete(freshDetail);
    relayCompleter.complete(
      const RelayData(currentAtBat: null, relayItems: []),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(
      find.text('game-detail-${liveGame.gameId}-tab-relay'),
      findsOneWidget,
    );
  });
}

PlayerProfile _playerProfile({required String name, required String id}) {
  return PlayerProfile(
    id: id,
    teamId: 'OB',
    name: name,
    number: 0,
    position: '',
    roleLabel: '',
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

String _todayKey() {
  final now = DateTime.now();
  return '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
}

var _appConfigInitialized = false;

void _ensureAppConfigInitialized() {
  if (_appConfigInitialized) {
    return;
  }
  AppConfig.initialize();
  _appConfigInitialized = true;
}

class _FixedMyTeamNotifier extends MyTeamNotifier {
  _FixedMyTeamNotifier(this.teamId);

  final String? teamId;

  @override
  String? build() => teamId;
}

GoRouter _homeInteractionRouter() {
  return GoRouter(
    initialLocation: '/home',
    routes: [
      GoRoute(path: '/home', builder: (_, _) => const HomeScreen()),
      GoRoute(
        path: '/records/team/:teamId',
        builder: (_, state) =>
            Text('team-record-${state.pathParameters['teamId']}'),
      ),
      GoRoute(path: '/records', builder: (_, _) => const Text('records')),
      GoRoute(path: '/standings', builder: (_, _) => const Text('standings')),
      GoRoute(path: '/news', builder: (_, _) => const Text('news')),
      GoRoute(path: '/onboarding', builder: (_, _) => const Text('onboarding')),
      GoRoute(path: '/settings', builder: (_, _) => const Text('settings')),
      GoRoute(
        path: '/notifications',
        builder: (_, _) => const Text('notifications'),
      ),
      GoRoute(
        path: '/game/:gameId',
        builder: (_, state) => Column(
          children: [
            Text(
              'game-detail-${state.pathParameters['gameId']}-tab-${state.uri.queryParameters['tab'] ?? ''}',
            ),
            Text(
              'game-detail-focus-${state.uri.queryParameters['focus'] ?? ''}',
            ),
          ],
        ),
      ),
    ],
  );
}

Widget _homeInteractionScope({
  required Widget child,
  HomeKboBrief? kboBrief,
  List<HomeQuickItem> quickItems = const [],
  List<Game>? scoreboardGames,
  List<TeamStanding>? standingsPreview,
}) {
  final standings = standingsPreview ?? _defaultHomeStandings();
  return ProviderScope(
    retry: (_, _) => null,
    overrides: [
      myTeamProvider.overrideWith(() => _FixedMyTeamNotifier('LG')),
      scoreboardProvider.overrideWith((ref, date) async {
        return scoreboardGames ??
            [
              _scheduledGame(
                gameId: '20260619SSLG0',
                awayTeamId: 'SS',
                awayShortName: '삼성',
                homeTeamId: 'LG',
                homeShortName: 'LG',
                stadium: '잠실',
              ),
            ];
      }),
      homeAggregateProvider.overrideWith((ref, key) async {
        return HomeAggregate(
          date: key.split('|').first,
          myTeam: 'LG',
          myTeamBrief: HomeMyTeamBrief(
            teamId: 'LG',
            teamLabel: 'LG 트윈스',
            standing: _standingByTeamId(standings, 'LG'),
            todayGameId: '20260619SSLG0',
            nextGame: null,
            recentWins: 4,
            recentLosses: 1,
            recentDraws: 0,
            recentGamesCount: 5,
            recentSummaries: const [
              HomeRecentGameSummary(
                gameId: 'recent-1',
                result: '승',
                opponentName: 'NC',
                score: '4:3',
              ),
              HomeRecentGameSummary(
                gameId: 'recent-2',
                result: '승',
                opponentName: 'NC',
                score: '7:1',
              ),
            ],
          ),
          kboBrief: kboBrief,
          quickItems: quickItems,
          standingsPreview: standings,
        );
      }),
    ],
    child: child,
  );
}

TeamStanding? _standingByTeamId(List<TeamStanding> standings, String teamId) {
  for (final standing in standings) {
    if (standing.teamId == teamId) {
      return standing;
    }
  }
  return null;
}

List<TeamStanding> _defaultHomeStandings() {
  return [
    _standing(
      rank: 1,
      teamId: 'HT',
      teamName: 'KIA 타이거즈',
      wins: 30,
      losses: 15,
      draws: 3,
      pct: '.667',
      gb: '-',
      streak: 'W2',
    ),
    _standing(
      rank: 2,
      teamId: 'LG',
      teamName: 'LG 트윈스',
      wins: 28,
      losses: 17,
      draws: 2,
      pct: '.622',
      gb: '2.0',
      streak: 'W4',
    ),
    _standing(
      rank: 3,
      teamId: 'SS',
      teamName: '삼성 라이온즈',
      wins: 24,
      losses: 21,
      draws: 1,
      pct: '.533',
      gb: '6.0',
      streak: 'W2',
    ),
    _standing(
      rank: 4,
      teamId: 'KT',
      teamName: 'KT 위즈',
      wins: 23,
      losses: 22,
      draws: 1,
      pct: '.511',
      gb: '7.0',
      streak: 'L1',
    ),
  ];
}

List<TeamStanding> _leagueStandings() {
  return [
    _standing(
      rank: 1,
      teamId: 'HT',
      teamName: 'KIA 타이거즈',
      wins: 40,
      losses: 20,
      draws: 2,
      pct: '.667',
      gb: '-',
      streak: 'W2',
    ),
    _standing(
      rank: 2,
      teamId: 'LG',
      teamName: 'LG 트윈스',
      wins: 38,
      losses: 22,
      draws: 2,
      pct: '.633',
      gb: '2.0',
      streak: 'W4',
    ),
    _standing(
      rank: 3,
      teamId: 'SS',
      teamName: '삼성 라이온즈',
      wins: 35,
      losses: 25,
      draws: 2,
      pct: '.583',
      gb: '5.0',
      streak: 'W1',
    ),
    _standing(
      rank: 4,
      teamId: 'OB',
      teamName: '두산 베어스',
      wins: 34,
      losses: 26,
      draws: 2,
      pct: '.567',
      gb: '6.0',
      streak: 'L1',
    ),
    _standing(
      rank: 5,
      teamId: 'NC',
      teamName: 'NC 다이노스',
      wins: 32,
      losses: 28,
      draws: 2,
      pct: '.533',
      gb: '8.0',
      streak: 'W3',
    ),
    _standing(
      rank: 6,
      teamId: 'KT',
      teamName: 'KT 위즈',
      wins: 30,
      losses: 30,
      draws: 2,
      pct: '.500',
      gb: '10.0',
      streak: 'L2',
    ),
    _standing(
      rank: 7,
      teamId: 'WO',
      teamName: '키움 히어로즈',
      wins: 28,
      losses: 32,
      draws: 2,
      pct: '.467',
      gb: '12.0',
      streak: 'W1',
    ),
    _standing(
      rank: 8,
      teamId: 'LT',
      teamName: '롯데 자이언츠',
      wins: 26,
      losses: 34,
      draws: 2,
      pct: '.433',
      gb: '14.0',
      streak: 'L1',
    ),
    _standing(
      rank: 9,
      teamId: 'HH',
      teamName: '한화 이글스',
      wins: 24,
      losses: 36,
      draws: 2,
      pct: '.400',
      gb: '16.0',
      streak: 'L3',
    ),
    _standing(
      rank: 10,
      teamId: 'SK',
      teamName: 'SSG 랜더스',
      wins: 22,
      losses: 38,
      draws: 2,
      pct: '.367',
      gb: '18.0',
      streak: 'W1',
    ),
  ];
}

TeamStanding _standing({
  required int rank,
  required String teamId,
  required String teamName,
  required int wins,
  required int losses,
  required int draws,
  required String pct,
  required String gb,
  required String streak,
}) {
  return TeamStanding(
    rank: rank,
    teamId: teamId,
    teamName: teamName,
    wins: wins,
    losses: losses,
    draws: draws,
    pct: pct,
    gb: gb,
    streak: streak,
  );
}

Game _liveGame({
  required String gameId,
  required String awayTeamId,
  required String homeTeamId,
}) {
  return Game(
    gameId: gameId,
    status: GameStatus.live,
    inning: '7회말',
    away: TeamScore(
      teamId: awayTeamId,
      teamName: awayTeamId,
      shortName: awayTeamId,
      score: 2,
      innings: const [],
    ),
    home: TeamScore(
      teamId: homeTeamId,
      teamName: homeTeamId,
      shortName: homeTeamId,
      score: 1,
      innings: const [],
    ),
    stadium: '잠실',
    startTime: '18:30',
  );
}

Game _scheduledGame({
  required String gameId,
  required String awayTeamId,
  required String awayShortName,
  required String homeTeamId,
  required String homeShortName,
  required String stadium,
}) {
  return Game(
    gameId: gameId,
    status: GameStatus.scheduled,
    inning: '18:30 예정',
    away: TeamScore(
      teamId: awayTeamId,
      teamName: awayShortName,
      shortName: awayShortName,
      score: 0,
      innings: const [],
    ),
    home: TeamScore(
      teamId: homeTeamId,
      teamName: homeShortName,
      shortName: homeShortName,
      score: 0,
      innings: const [],
    ),
    stadium: stadium,
    startTime: '18:30',
  );
}
