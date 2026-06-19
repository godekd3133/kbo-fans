import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:kbo_fans/core/config/app_config.dart';
import 'package:kbo_fans/core/widgets/main_scaffold.dart';
import 'package:kbo_fans/data/models/schedule.dart';
import 'package:kbo_fans/data/providers.dart';
import 'package:kbo_fans/features/schedule/schedule_screen.dart';

void main() {
  setUpAll(() {
    AppConfig.initialize();
  });

  testWidgets('일정 초기 로딩은 새로고침 indicator와 중복되지 않는다', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          scheduleProvider.overrideWith(
            (_, _) => Completer<List<ScheduleDay>>().future,
          ),
        ],
        child: const MaterialApp(home: ScheduleScreen()),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(RefreshIndicator), findsNothing);
  });

  testWidgets('월 데이터 실패 상태에서도 헤더 월 이동은 동작한다', (tester) async {
    final now = DateTime.now();
    final nextMonth = DateTime(now.year, now.month + 1);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          scheduleProvider.overrideWith(
            (_, _) => Future.error('schedule down'),
          ),
        ],
        child: const MaterialApp(home: ScheduleScreen()),
      ),
    );
    await tester.pump();

    expect(find.text(_monthLabel(now)), findsOneWidget);

    await tester.tap(find.byIcon(Icons.chevron_right_rounded));
    await tester.pumpAndSettle();

    expect(find.text(_monthLabel(nextMonth)), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('캘린더 영역에서 위로 밀어도 선택일 경기 목록이 스크롤된다', (tester) async {
    final now = DateTime.now();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          scheduleProvider.overrideWith(
            (_, yearMonth) async => _longScheduleForToday(now, yearMonth),
          ),
        ],
        child: const MaterialApp(home: ScheduleScreen()),
      ),
    );
    await tester.pumpAndSettle();

    final firstGame = find.text('Away 0');
    expect(firstGame, findsOneWidget);
    final initialTop = tester.getTopLeft(firstGame).dy;

    await tester.drag(find.text('일반 경기일'), const Offset(0, -180));
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(firstGame).dy, lessThan(initialTop));
  });

  testWidgets('이미 선택된 일정 탭을 다시 눌러도 선택 월을 유지한다', (tester) async {
    final now = DateTime.now();
    final nextMonth = DateTime(now.year, now.month + 1);
    final router = GoRouter(
      initialLocation: '/schedule',
      routes: [
        ShellRoute(
          builder: (context, state, child) => MainScaffold(child: child),
          routes: [
            GoRoute(
              path: '/home',
              builder: (context, state) => const SizedBox.shrink(),
            ),
            GoRoute(
              path: '/schedule',
              builder: (context, state) => const ScheduleScreen(),
            ),
            GoRoute(
              path: '/standings',
              builder: (context, state) => const SizedBox.shrink(),
            ),
            GoRoute(
              path: '/records',
              builder: (context, state) => const SizedBox.shrink(),
            ),
            GoRoute(
              path: '/settings',
              builder: (context, state) => const SizedBox.shrink(),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          scheduleProvider.overrideWith(
            (_, yearMonth) async => _scheduleForMonth(yearMonth),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.chevron_right_rounded));
    await tester.pumpAndSettle();

    expect(find.text(_monthLabel(nextMonth)), findsOneWidget);

    await tester.tap(find.byIcon(Icons.sports_baseball_rounded));
    await tester.pumpAndSettle();

    expect(find.text(_monthLabel(nextMonth)), findsOneWidget);
  });
}

String _monthLabel(DateTime month) {
  return DateFormat('MMM yyyy', 'en_US').format(month).toUpperCase();
}

List<ScheduleDay> _scheduleForMonth(String yearMonth) {
  return [ScheduleDay(date: '$yearMonth-01', games: const [])];
}

List<ScheduleDay> _longScheduleForToday(DateTime today, String yearMonth) {
  final currentYearMonth =
      '${today.year}-${today.month.toString().padLeft(2, '0')}';
  if (yearMonth != currentYearMonth) {
    return const [];
  }

  return [
    ScheduleDay(
      date: '$yearMonth-${today.day.toString().padLeft(2, '0')}',
      games: List.generate(
        18,
        (index) => ScheduleGame(
          gameId: 'scroll-test-$index',
          time: '18:${index.toString().padLeft(2, '0')}',
          awayId: 'AW$index',
          awayName: 'Away $index',
          homeId: 'HM$index',
          homeName: 'Home $index',
          stadium: '테스트 구장',
        ),
      ),
    ),
  ];
}
