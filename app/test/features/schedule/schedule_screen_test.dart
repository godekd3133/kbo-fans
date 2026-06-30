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

  testWidgets('캘린더의 다음달 1일을 누르면 다음달로 이동한다', (tester) async {
    final now = DateTime.now();
    final visibleMonth = _monthWithVisibleNextMonthDay(now);
    final nextMonth = DateTime(visibleMonth.year, visibleMonth.month + 1);
    final monthDelta =
        (visibleMonth.year - now.year) * 12 + visibleMonth.month - now.month;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          scheduleProvider.overrideWith(
            (_, yearMonth) async => _singleGameOnFirstDaySchedule(yearMonth),
          ),
        ],
        child: const MaterialApp(home: ScheduleScreen()),
      ),
    );
    await tester.pumpAndSettle();

    for (var i = 0; i < monthDelta; i += 1) {
      await tester.tap(find.byIcon(Icons.chevron_right_rounded));
      await tester.pumpAndSettle();
    }

    expect(find.text(_monthLabel(visibleMonth)), findsOneWidget);

    await tester.tap(find.text('1').last);
    await tester.pumpAndSettle();

    expect(find.text(_monthLabel(nextMonth)), findsOneWidget);
    expect(find.text('Away 1'), findsOneWidget);
  });

  testWidgets('매치업 탭은 선택한 두 팀의 맞대결 일정만 보여준다', (tester) async {
    final now = DateTime.now();
    final yearMonth = '${now.year}-${now.month.toString().padLeft(2, '0')}';

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          myTeamProvider.overrideWith(() => _FixedMyTeamNotifier('LG')),
          scheduleProvider.overrideWith(
            (_, month) async => _matchupScheduleForMonth(yearMonth, month),
          ),
        ],
        child: const MaterialApp(home: ScheduleScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('매치업'));
    await tester.pumpAndSettle();

    expect(find.text('잠실 LG-KT'), findsOneWidget);
    expect(find.text('잠실 LG-SSG'), findsNothing);
    expect(find.text('사직 롯데-두산'), findsNothing);

    await tester.tap(find.text('SSG').last);
    await tester.pumpAndSettle();

    expect(find.text('잠실 LG-KT'), findsNothing);
    expect(find.text('잠실 LG-SSG'), findsOneWidget);
    expect(find.text('사직 롯데-두산'), findsNothing);
  });

  testWidgets('매치업 탭은 시즌 전체 일정을 오늘 가까운 순으로 보여주고 지난 경기를 어둡게 표시한다', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final today = DateTime.now();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          myTeamProvider.overrideWith(() => _FixedMyTeamNotifier('LG')),
          scheduleProvider.overrideWith(
            (_, month) async => _seasonWideMatchupSchedule(today, month),
          ),
        ],
        child: const MaterialApp(home: ScheduleScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('매치업'));
    await tester.pumpAndSettle();

    expect(find.text('오늘 LG-KT'), findsOneWidget);
    expect(find.text('내일 LG-KT'), findsOneWidget);
    expect(find.text('어제 LG-KT'), findsOneWidget);
    expect(find.text('다음달 LG-KT'), findsOneWidget);
    expect(find.text('LG-SSG 제외'), findsNothing);

    final todayTop = tester.getTopLeft(find.text('오늘 LG-KT')).dy;
    final tomorrowTop = tester.getTopLeft(find.text('내일 LG-KT')).dy;
    final yesterdayTop = tester.getTopLeft(find.text('어제 LG-KT')).dy;
    final nextMonthTop = tester.getTopLeft(find.text('다음달 LG-KT')).dy;

    expect(todayTop, lessThan(tomorrowTop));
    expect(tomorrowTop, lessThan(yesterdayTop));
    expect(yesterdayTop, lessThan(nextMonthTop));

    final pastOpacity = tester.widget<Opacity>(
      find.byKey(const ValueKey('matchup-game-opacity-yesterday-lg-kt')),
    );
    expect(pastOpacity.opacity, lessThan(1));
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

  testWidgets('마이팀 경기는 일정 카드에서 강조된다', (tester) async {
    final now = DateTime.now();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          myTeamProvider.overrideWith(() => _FixedMyTeamNotifier('LG')),
          scheduleProvider.overrideWith(
            (_, yearMonth) async => _myTeamScheduleForToday(now, yearMonth),
          ),
        ],
        child: const MaterialApp(home: ScheduleScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('schedule-my-team-badge-today-lg')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('schedule-my-team-badge-today-nc-ob')),
      findsNothing,
    );
  });
}

String _monthLabel(DateTime month) {
  return DateFormat('MMM yyyy', 'en_US').format(month).toUpperCase();
}

DateTime _monthWithVisibleNextMonthDay(DateTime start) {
  for (var offset = 0; offset < 12; offset += 1) {
    final month = DateTime(start.year, start.month + offset);
    final lastDay = DateTime(month.year, month.month + 1, 0);
    if (lastDay.weekday != DateTime.sunday) {
      return month;
    }
  }

  throw StateError('No month with visible next-month day found');
}

List<ScheduleDay> _scheduleForMonth(String yearMonth) {
  return [ScheduleDay(date: '$yearMonth-01', games: const [])];
}

List<ScheduleDay> _singleGameOnFirstDaySchedule(String yearMonth) {
  return [
    ScheduleDay(
      date: '$yearMonth-01',
      games: const [
        ScheduleGame(
          gameId: 'next-month-1',
          time: '18:30',
          awayId: 'AW1',
          awayName: 'Away 1',
          homeId: 'HM1',
          homeName: 'Home 1',
          stadium: '테스트 구장',
        ),
      ],
    ),
  ];
}

List<ScheduleDay> _matchupScheduleForMonth(
  String currentYearMonth,
  String requestedYearMonth,
) {
  if (requestedYearMonth != currentYearMonth) {
    return const [];
  }

  return [
    ScheduleDay(
      date: '$requestedYearMonth-03',
      games: const [
        ScheduleGame(
          gameId: 'lg-kt',
          time: '18:30',
          awayId: 'KT',
          awayName: 'KT 위즈',
          homeId: 'LG',
          homeName: 'LG 트윈스',
          stadium: '잠실 LG-KT',
        ),
        ScheduleGame(
          gameId: 'lt-ob',
          time: '18:30',
          awayId: 'OB',
          awayName: '두산 베어스',
          homeId: 'LT',
          homeName: '롯데 자이언츠',
          stadium: '사직 롯데-두산',
        ),
      ],
    ),
    ScheduleDay(
      date: '$requestedYearMonth-17',
      games: const [
        ScheduleGame(
          gameId: 'lg-sk',
          time: '18:30',
          awayId: 'LG',
          awayName: 'LG 트윈스',
          homeId: 'SK',
          homeName: 'SSG 랜더스',
          stadium: '잠실 LG-SSG',
        ),
      ],
    ),
  ];
}

List<ScheduleDay> _seasonWideMatchupSchedule(
  DateTime today,
  String requestedYearMonth,
) {
  final dateToday = _dateOnly(today);
  final yesterday = dateToday.subtract(const Duration(days: 1));
  final tomorrow = dateToday.add(const Duration(days: 1));
  final nextMonth = DateTime(dateToday.year, dateToday.month + 1, 10);

  final days = <DateTime, List<ScheduleGame>>{
    dateToday: const [
      ScheduleGame(
        gameId: 'today-lg-kt',
        time: '18:30',
        awayId: 'LG',
        awayName: 'LG 트윈스',
        homeId: 'KT',
        homeName: 'KT 위즈',
        stadium: '오늘 LG-KT',
      ),
      ScheduleGame(
        gameId: 'today-lg-sk',
        time: '18:30',
        awayId: 'LG',
        awayName: 'LG 트윈스',
        homeId: 'SK',
        homeName: 'SSG 랜더스',
        stadium: 'LG-SSG 제외',
      ),
    ],
    tomorrow: const [
      ScheduleGame(
        gameId: 'tomorrow-lg-kt',
        time: '18:30',
        awayId: 'KT',
        awayName: 'KT 위즈',
        homeId: 'LG',
        homeName: 'LG 트윈스',
        stadium: '내일 LG-KT',
      ),
    ],
    yesterday: const [
      ScheduleGame(
        gameId: 'yesterday-lg-kt',
        time: '18:30',
        awayId: 'LG',
        awayName: 'LG 트윈스',
        homeId: 'KT',
        homeName: 'KT 위즈',
        stadium: '어제 LG-KT',
        status: 'FINAL',
        awayScore: 4,
        homeScore: 2,
      ),
    ],
    nextMonth: const [
      ScheduleGame(
        gameId: 'next-month-lg-kt',
        time: '18:30',
        awayId: 'KT',
        awayName: 'KT 위즈',
        homeId: 'LG',
        homeName: 'LG 트윈스',
        stadium: '다음달 LG-KT',
      ),
    ],
  };

  return days.entries
      .where((entry) => _yearMonthKey(entry.key) == requestedYearMonth)
      .map(
        (entry) => ScheduleDay(date: _dateKey(entry.key), games: entry.value),
      )
      .toList();
}

DateTime _dateOnly(DateTime date) {
  return DateTime(date.year, date.month, date.day);
}

String _yearMonthKey(DateTime date) {
  return '${date.year}-${date.month.toString().padLeft(2, '0')}';
}

String _dateKey(DateTime date) {
  return '${_yearMonthKey(date)}-${date.day.toString().padLeft(2, '0')}';
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

List<ScheduleDay> _myTeamScheduleForToday(DateTime today, String yearMonth) {
  final currentYearMonth =
      '${today.year}-${today.month.toString().padLeft(2, '0')}';
  if (yearMonth != currentYearMonth) {
    return const [];
  }

  return [
    ScheduleDay(
      date: '$yearMonth-${today.day.toString().padLeft(2, '0')}',
      games: const [
        ScheduleGame(
          gameId: 'today-lg',
          time: '18:30',
          awayId: 'LG',
          awayName: 'LG',
          homeId: 'KT',
          homeName: 'KT',
          stadium: '잠실',
          status: 'SCHEDULED',
        ),
        ScheduleGame(
          gameId: 'today-nc-ob',
          time: '18:30',
          awayId: 'NC',
          awayName: 'NC',
          homeId: 'OB',
          homeName: '두산',
          stadium: '창원',
          status: 'SCHEDULED',
        ),
      ],
    ),
  ];
}

class _FixedMyTeamNotifier extends MyTeamNotifier {
  _FixedMyTeamNotifier(this.teamId);

  final String? teamId;

  @override
  String? build() => teamId;
}
