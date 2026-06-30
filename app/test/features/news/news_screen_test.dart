import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kbo_fans/core/theme/app_theme.dart';
import 'package:kbo_fans/data/models/home_aggregate.dart';
import 'package:kbo_fans/data/models/schedule.dart';
import 'package:kbo_fans/data/providers.dart';
import 'package:kbo_fans/features/news/news_screen.dart';

void main() {
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
                    title: 'LG 트윈스 1위 유지',
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

    expect(find.text('뉴스'), findsOneWidget);
    expect(find.text('주요 소식'), findsOneWidget);
    expect(find.text('지금 KBO'), findsNothing);
    expect(find.text('2경기 진행 중'), findsNothing);
    expect(find.text('오늘의 3분 브리핑'), findsNothing);
    expect(find.text('최신 뉴스'), findsOneWidget);
    expect(find.text('LG 트윈스 1위 유지'), findsWidgets);
    expect(find.text('김도영 13개'), findsWidgets);
    expect(find.text('순위 보기'), findsWidgets);
    expect(find.text('기록 보기'), findsWidgets);
    expect(find.text('삼라'), findsNothing);
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
    expect(find.text('KIA 타이거즈 1위'), findsWidgets);
    expect(find.text('오늘 3경기'), findsWidgets);
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
    expect(find.text('기록 보기'), findsWidgets);
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

    expect(find.text('오늘 보여줄 뉴스가 없습니다'), findsOneWidget);
    expect(find.text('일정 보기'), findsOneWidget);
  });
}
