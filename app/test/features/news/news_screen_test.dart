import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kbo_fans/core/theme/app_theme.dart';
import 'package:kbo_fans/data/models/home_aggregate.dart';
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
              quickItems: const [],
            );
          }),
        ],
        child: MaterialApp(theme: AppTheme.dark, home: const NewsScreen()),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('뉴스'), findsOneWidget);
    expect(find.text('지금 KBO'), findsOneWidget);
    expect(find.text('LG 트윈스 1위 유지'), findsOneWidget);
    expect(find.text('순위 보기'), findsOneWidget);
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
