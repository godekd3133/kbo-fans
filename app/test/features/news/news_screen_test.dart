import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kbo_fans/core/router/app_router.dart';
import 'package:kbo_fans/core/theme/app_theme.dart';
import 'package:kbo_fans/data/models/home_aggregate.dart';
import 'package:kbo_fans/data/models/schedule.dart';
import 'package:kbo_fans/data/providers.dart';
import 'package:kbo_fans/features/news/news_screen.dart';

void main() {
  testWidgets('news requests the current KBO civil date', (tester) async {
    String? requestedKey;
    final expectedDate = _kboDateKey(DateTime.now());

    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          homeAggregateProvider.overrideWith((ref, key) async {
            requestedKey = key;
            return HomeAggregate(
              date: key.split('|').first,
              myTeam: null,
              myTeamBrief: null,
              kboBrief: null,
              quickItems: const [],
              generatedAt: DateTime.fromMillisecondsSinceEpoch(
                1700000000000,
                isUtc: true,
              ),
            );
          }),
        ],
        child: MaterialApp(theme: AppTheme.dark, home: const NewsScreen()),
      ),
    );
    await tester.pump();

    expect(requestedKey?.split('|').first, expectedDate);
    expect(
      find.text('${expectedDate.replaceAll('-', '.')} 기준'),
      findsOneWidget,
    );
    expect(find.textContaining('07:13 생성'), findsOneWidget);
  });

  testWidgets('브리핑은 KST 자정 rollover와 즉시 새로고침에 최신 날짜 key를 쓴다', (tester) async {
    const beforeMidnight = '2026-12-31';
    const afterMidnight = '2027-01-01';
    final requestedKeys = <String>[];
    final container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        homeAggregateProvider.overrideWith((ref, key) async {
          requestedKeys.add(key);
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
    container
        .read(kboDateProvider.notifier)
        .refresh(instant: DateTime.utc(2026, 12, 31, 14, 59));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: AppTheme.dark, home: const NewsScreen()),
      ),
    );
    await tester.pump();

    expect(requestedKeys.last.split('|').first, beforeMidnight);
    expect(find.text('2026.12.31 기준'), findsOneWidget);

    requestedKeys.clear();
    container
        .read(kboDateProvider.notifier)
        .refresh(instant: DateTime.utc(2026, 12, 31, 15));
    await tester.tap(find.byTooltip('데이터 브리핑 새로고침'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(requestedKeys, isNotEmpty);
    expect(requestedKeys.first.split('|').first, afterMidnight);
    expect(find.text('2027.01.01 기준'), findsOneWidget);
  });

  testWidgets('320px·240% 브리핑 필터는 모든 이름을 줄임표 없이 재배치한다', (tester) async {
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
        child: MaterialApp(theme: AppTheme.dark, home: const NewsScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.scrollUntilVisible(
      find.text('전체'),
      240,
      scrollable: find.byType(Scrollable).first,
    );

    for (final label in ['전체', '경기', '순위', '기록', '마이팀']) {
      final textFinder = find.text(label);
      expect(textFinder, findsOneWidget);
      expect(
        tester.widget<Text>(textFinder).overflow,
        isNot(TextOverflow.ellipsis),
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('news cards push shell screens with iOS swipe-back routes', (
    tester,
  ) async {
    final container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        homeAggregateProvider.overrideWith((ref, key) async {
          return HomeAggregate(
            date: key.split('|').first,
            myTeam: null,
            myTeamBrief: null,
            kboBrief: const HomeKboBrief(
              title: '지금 KBO',
              subtitle: '순위 흐름',
              items: [
                HomeKboBriefItem(
                  type: 'standings',
                  eyebrow: '선두권',
                  title: 'LG 트윈스 1위 유지',
                  subtitle: '2위와 1.5G차',
                  route: '/standings',
                ),
              ],
            ),
            quickItems: const [],
          );
        }),
        standingsProvider.overrideWith((ref, season) async => <TeamStanding>[]),
      ],
    );
    addTearDown(container.dispose);
    container.read(onboardingDoneProvider.notifier).setValue(true);
    final router = container.read(routerProvider);
    router.go('/news');

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.text('선두가 위태로운 LG 트윈스').last);
    await tester.pump();

    final shellNavigator = tester
        .widgetList<Navigator>(find.byType(Navigator))
        .last;
    expect(shellNavigator.pages.last, isA<CupertinoPage<void>>());
  });

  testWidgets('renders news cards from home aggregate brief items', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          homeAggregateProvider.overrideWith((ref, key) async {
            return HomeAggregate(
              date: key.split('|').first,
              myTeam: null,
              myTeamBrief: null,
              kboBrief: const HomeKboBrief(
                title: '지금 KBO',
                subtitle: '2경기 진행 중',
                items: [
                  HomeKboBriefItem(
                    type: 'standings',
                    eyebrow: '선두권',
                    title: '선두가 위태로운 LG 트윈스',
                    subtitle: '2위와 1.5G차',
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
            );
          }),
        ],
        child: MaterialApp(theme: AppTheme.dark, home: const NewsScreen()),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('데이터 브리핑'), findsOneWidget);
    expect(find.text('먼저 볼 흐름'), findsOneWidget);
    expect(find.textContaining('실제 뉴스 기사 아님'), findsOneWidget);
    expect(find.text('지금 KBO'), findsNothing);
    expect(find.text('2경기 진행 중'), findsNothing);
    expect(find.text('오늘의 3분 브리핑'), findsNothing);
    expect(find.text('전체 데이터 흐름'), findsOneWidget);
    expect(find.text('선두가 위태로운 LG 트윈스'), findsWidgets);
    expect(find.text('선두가 위태로운 선두가 위태로운 LG 트윈스'), findsNothing);
    expect(find.text('김도영 13개'), findsWidgets);
    expect(find.text('순위 보기'), findsWidgets);
    expect(find.text('기록 보기'), findsWidgets);
    expect(find.text('삼라'), findsNothing);
    expect(
      tester
          .widgetList<Icon>(find.byIcon(Icons.chevron_right_rounded))
          .every((icon) => icon.color == AppTheme.darkColors.textSupporting),
      isTrue,
    );
  });

  testWidgets('derives diverse news from my team and standings preview', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          homeAggregateProvider.overrideWith((ref, key) async {
            return HomeAggregate(
              date: key.split('|').first,
              myTeam: 'LG',
              myTeamBrief: const HomeMyTeamBrief(
                teamId: 'LG',
                teamLabel: 'LG 트윈스',
                standing: null,
                todayGameId: '20260619SSLG0',
                nextGame: null,
                recentWins: 2,
                recentLosses: 1,
                recentDraws: 0,
                recentGamesCount: 3,
                recentSummaries: [
                  HomeRecentGameSummary(
                    gameId: '20260618LGLT0',
                    result: '승',
                    opponentName: '롯데',
                    score: '5:2',
                  ),
                ],
              ),
              kboBrief: const HomeKboBrief(
                title: '오늘의 KBO 소식',
                subtitle: '지금 볼 장면 8개',
                items: [
                  HomeKboBriefItem(
                    type: 'player_performance',
                    eyebrow: '선수',
                    title: '구자욱 장타율 상승',
                    subtitle: '최근 7경기 장타 5개',
                    route: '/records/player/62415?season=2026',
                    fallbackLabel: '구자욱',
                  ),
                ],
              ),
              quickItems: const [
                HomeQuickItem(
                  eyebrow: '오늘 일정',
                  title: '오늘 3경기',
                  subtitle: '남은 경기 2',
                  route: '/schedule',
                ),
              ],
              standingsPreview: const [
                TeamStanding(
                  rank: 1,
                  teamId: 'HT',
                  teamName: 'KIA 타이거즈',
                  wins: 30,
                  losses: 15,
                  draws: 3,
                  pct: '.667',
                  gb: '-',
                  streak: 'W3',
                ),
              ],
            );
          }),
        ],
        child: MaterialApp(theme: AppTheme.dark, home: const NewsScreen()),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('선수'), findsWidgets);
    expect(find.text('마이팀'), findsWidgets);
    expect(find.text('LG 트윈스 승 · 롯데전 5:2'), findsOneWidget);
    expect(find.text('선두 지키는 KIA 타이거즈'), findsWidgets);
    expect(find.text('오늘 3경기'), findsWidgets);
  });

  testWidgets('expands standings into at least 25 visible latest news rows', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          homeAggregateProvider.overrideWith((ref, key) async {
            return HomeAggregate(
              date: key.split('|').first,
              myTeam: null,
              myTeamBrief: null,
              kboBrief: null,
              quickItems: const [],
              standingsPreview: const [
                TeamStanding(
                  rank: 1,
                  teamId: 'LG',
                  teamName: 'LG 트윈스',
                  wins: 42,
                  losses: 25,
                  draws: 2,
                  pct: '.627',
                  gb: '-',
                ),
                TeamStanding(
                  rank: 2,
                  teamId: 'HH',
                  teamName: '한화 이글스',
                  wins: 41,
                  losses: 26,
                  draws: 2,
                  pct: '.612',
                  gb: '1.0',
                ),
                TeamStanding(
                  rank: 3,
                  teamId: 'LT',
                  teamName: '롯데 자이언츠',
                  wins: 39,
                  losses: 28,
                  draws: 2,
                  pct: '.582',
                  gb: '3.0',
                ),
                TeamStanding(
                  rank: 4,
                  teamId: 'HT',
                  teamName: 'KIA 타이거즈',
                  wins: 37,
                  losses: 30,
                  draws: 2,
                  pct: '.552',
                  gb: '5.0',
                ),
                TeamStanding(
                  rank: 5,
                  teamId: 'SK',
                  teamName: 'SSG 랜더스',
                  wins: 35,
                  losses: 32,
                  draws: 2,
                  pct: '.522',
                  gb: '7.0',
                ),
                TeamStanding(
                  rank: 6,
                  teamId: 'SS',
                  teamName: '삼성 라이온즈',
                  wins: 33,
                  losses: 34,
                  draws: 2,
                  pct: '.493',
                  gb: '9.0',
                ),
                TeamStanding(
                  rank: 7,
                  teamId: 'KT',
                  teamName: 'KT 위즈',
                  wins: 31,
                  losses: 36,
                  draws: 2,
                  pct: '.463',
                  gb: '11.0',
                ),
                TeamStanding(
                  rank: 8,
                  teamId: 'NC',
                  teamName: 'NC 다이노스',
                  wins: 30,
                  losses: 37,
                  draws: 2,
                  pct: '.448',
                  gb: '12.0',
                ),
                TeamStanding(
                  rank: 9,
                  teamId: 'OB',
                  teamName: '두산 베어스',
                  wins: 28,
                  losses: 39,
                  draws: 2,
                  pct: '.418',
                  gb: '14.0',
                ),
                TeamStanding(
                  rank: 10,
                  teamId: 'WO',
                  teamName: '키움 히어로즈',
                  wins: 24,
                  losses: 43,
                  draws: 2,
                  pct: '.358',
                  gb: '18.0',
                ),
              ],
            );
          }),
        ],
        child: MaterialApp(theme: AppTheme.dark, home: const NewsScreen()),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('27개'), findsOneWidget);
    expect(find.text('선두가 위태로운 LG 트윈스'), findsWidgets);
    expect(find.text('LG 트윈스 턱밑까지 쫓는 한화 이글스'), findsWidgets);
    expect(find.text('LG 트윈스, 지금 페이스면 88승'), findsWidgets);
  });

  testWidgets('classifies defense and batting brief items as records news', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          homeAggregateProvider.overrideWith((ref, key) async {
            return HomeAggregate(
              date: key.split('|').first,
              myTeam: null,
              myTeamBrief: null,
              kboBrief: const HomeKboBrief(
                title: '오늘의 KBO 소식',
                subtitle: '실책과 타율 흐름',
                items: [
                  HomeKboBriefItem(
                    type: 'defense_issue',
                    eyebrow: '실책 많은 경기',
                    title: '두산-LG 합계 5실책',
                    subtitle: '두산 3실책 · LG 2실책',
                    route: '/game/20260629OBLG0',
                    teamIds: ['OB', 'LG'],
                  ),
                  HomeKboBriefItem(
                    type: 'batting_leader',
                    eyebrow: '6월 현재 타율',
                    title: '홍창기 타율 0.351',
                    subtitle: 'LG 트윈스 · 시즌 타율 1위',
                    route: '/records/player/64166?season=2026',
                    teamIds: ['LG'],
                    fallbackLabel: '홍창기',
                  ),
                  HomeKboBriefItem(
                    type: 'defense_rank',
                    eyebrow: '팀별 실책',
                    title: '두산 3개 · LG 2개',
                    subtitle: '6월 29일 경기 기준 · 실책 많은 팀 순',
                    route: '/schedule',
                    teamIds: ['OB', 'LG'],
                  ),
                  HomeKboBriefItem(
                    type: 'record_milestone',
                    eyebrow: '기록 달성',
                    title: '최형우 2000루타 달성',
                    subtitle: 'KIA 타이거즈 · 역대 3번째',
                    route: '/records/player/78224?season=2026',
                    teamIds: ['HT'],
                    fallbackLabel: '최형우',
                  ),
                ],
              ),
              quickItems: const [],
            );
          }),
        ],
        child: MaterialApp(theme: AppTheme.dark, home: const NewsScreen()),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('두산-LG 합계 5실책'), findsWidgets);
    expect(find.text('홍창기 타율 0.351'), findsWidgets);
    expect(find.text('두산 3개 · LG 2개'), findsWidgets);
    expect(find.text('최형우 2000루타 달성'), findsWidgets);
    expect(find.text('기록 보기'), findsWidgets);

    await tester.tap(find.text('기록').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('최형우 2000루타 달성'), findsNWidgets(2));
  });

  testWidgets('derives pace news from home run leader and standings', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          homeAggregateProvider.overrideWith((ref, key) async {
            return HomeAggregate(
              date: '2026-06-30',
              myTeam: null,
              myTeamBrief: null,
              kboBrief: null,
              quickItems: const [
                HomeQuickItem(
                  eyebrow: '홈런왕',
                  title: '김도영 20개',
                  subtitle: 'KIA 타이거즈 · 시즌 홈런 1위',
                  route: '/records/player/52605?season=2026',
                  teamId: 'HT',
                  fallbackLabel: '김도영',
                ),
              ],
              standingsPreview: const [
                TeamStanding(
                  rank: 1,
                  teamId: 'HT',
                  teamName: 'KIA 타이거즈',
                  wins: 35,
                  losses: 20,
                  draws: 1,
                  pct: '.636',
                  gb: '-',
                  streak: 'L3',
                ),
                TeamStanding(
                  rank: 6,
                  teamId: 'LG',
                  teamName: 'LG 트윈스',
                  wins: 26,
                  losses: 30,
                  draws: 0,
                  pct: '.464',
                  gb: '8.0',
                  streak: 'W4',
                ),
              ],
            );
          }),
        ],
        child: MaterialApp(theme: AppTheme.dark, home: const NewsScreen()),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('김도영, 지금 페이스면 51홈런'), findsOneWidget);
    expect(find.text('앱 계산 · KIA 타이거즈 56경기 기준 · 현재 20홈런'), findsOneWidget);
    expect(find.text('KIA 타이거즈, 지금 페이스면 90승'), findsWidgets);
    await tester.scrollUntilVisible(
      find.textContaining('3연패').first,
      180,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('3연패'), findsWidgets);

    await tester.scrollUntilVisible(
      find.textContaining('4연승').first,
      180,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('4연승'), findsWidgets);
  });

  testWidgets('renders empty state when aggregate has no news items', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
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
        child: MaterialApp(theme: AppTheme.dark, home: const NewsScreen()),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('오늘 정리할 데이터 흐름이 없습니다'), findsOneWidget);
    expect(find.text('일정 보기'), findsOneWidget);
  });
}

String _kboDateKey(DateTime instant) {
  final kbo = instant.toUtc().add(const Duration(hours: 9));
  return '${kbo.year.toString().padLeft(4, '0')}-'
      '${kbo.month.toString().padLeft(2, '0')}-'
      '${kbo.day.toString().padLeft(2, '0')}';
}
