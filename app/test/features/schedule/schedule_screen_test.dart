import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kbo_fans/core/theme/app_theme.dart';
import 'package:kbo_fans/core/utils/kbo_time.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:kbo_fans/core/config/app_config.dart';
import 'package:kbo_fans/core/widgets/app_motion.dart';
import 'package:kbo_fans/core/widgets/main_scaffold.dart';
import 'package:kbo_fans/data/models/boxscore.dart';
import 'package:kbo_fans/data/models/game.dart';
import 'package:kbo_fans/data/models/player.dart';
import 'package:kbo_fans/data/models/relay.dart';
import 'package:kbo_fans/data/models/schedule.dart';
import 'package:kbo_fans/data/models/ticketing.dart';
import 'package:kbo_fans/data/providers.dart';
import 'package:kbo_fans/features/schedule/schedule_screen.dart';

void main() {
  setUpAll(() {
    AppConfig.initialize();
  });

  test('예매 시각은 KST와 공식·예상 출처를 구분한다', () {
    expect(
      formatScheduleTicketSummary(
        TicketInfo(
          vendorKey: 'interpark',
          vendorName: '인터파크 티켓',
          openAt: DateTime.utc(2026, 7, 13, 2),
          source: TicketSource.inferred,
        ),
      ),
      '인터파크 티켓 · 07.13 11:00 KST 예상 오픈',
    );
    expect(
      formatScheduleTicketSummary(
        TicketInfo(
          vendorKey: 'ticketlink',
          vendorName: '티켓링크',
          openAt: DateTime.utc(2026, 7, 13, 2),
          source: TicketSource.official,
        ),
      ),
      '티켓링크 · 07.13 11:00 KST 공식 오픈',
    );
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
    final now = kboCivilDateTime();
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

  testWidgets('마이팀이 없으면 일정 기본 보기를 개인화된 것처럼 부르지 않는다', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          scheduleProvider.overrideWith(
            (_, yearMonth) async => _scheduleForMonth(yearMonth),
          ),
        ],
        child: const MaterialApp(home: ScheduleScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('달력 보기'), findsOneWidget);
    expect(find.text('내 팀 먼저 보기'), findsNothing);
  });

  testWidgets('320px·240% 일정의 선택 가능한 보조 정보는 지원 텍스트로 유지된다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    tester.platformDispatcher.textScaleFactorTestValue = 2.4;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final now = kboCivilDateTime();
    final monthEyebrow = DateFormat(
      'MMM yyyy',
      'en_US',
    ).format(now).toUpperCase();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [scheduleProvider.overrideWith((_, _) async => const [])],
        child: MaterialApp(theme: AppTheme.dark, home: const ScheduleScreen()),
      ),
    );
    await tester.pumpAndSettle();

    final eyebrow = tester.widget<Text>(find.text(monthEyebrow));
    final legend = tester.widget<Text>(find.text('일반 경기'));
    expect(eyebrow.style?.color, AppTheme.darkColors.textSupporting);
    expect(legend.style?.color, AppTheme.darkColors.textSupporting);
    expect(tester.takeException(), isNull);
  });

  testWidgets('320px 일정 달력은 수평 스크롤 없이 일요일 열까지 보인다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [scheduleProvider.overrideWith((_, _) async => const [])],
        child: MaterialApp(theme: AppTheme.dark, home: const ScheduleScreen()),
      ),
    );
    await tester.pumpAndSettle();

    final calendar = find.byKey(const ValueKey('schedule-calendar-card'));
    expect(tester.getSize(calendar).width, lessThanOrEqualTo(320));
    expect(find.text('일'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('캘린더의 다음달 1일을 누르면 다음달로 이동한다', (tester) async {
    final now = kboCivilDateTime();
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
    final now = kboCivilDateTime();
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

  testWidgets('매치업 탭은 시즌 전체 남은 일정을 오늘 기준 가까운 순으로 보여준다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final today = kboCivilDateTime();

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
    expect(find.text('어제 LG-KT'), findsNothing);
    expect(find.text('다음달 LG-KT'), findsOneWidget);
    expect(find.text('LG-SSG 제외'), findsNothing);
    expect(find.text('오늘 진행 중 LG-KT'), findsNothing);
    expect(find.text('오늘 종료 LG-KT'), findsNothing);
    expect(find.text('오늘 취소 LG-KT'), findsNothing);
    expect(find.textContaining('남은 3경기'), findsOneWidget);

    final todayTop = tester.getTopLeft(find.text('오늘 LG-KT')).dy;
    final tomorrowTop = tester.getTopLeft(find.text('내일 LG-KT')).dy;
    final nextMonthTop = tester.getTopLeft(find.text('다음달 LG-KT')).dy;

    expect(todayTop, lessThan(tomorrowTop));
    expect(tomorrowTop, lessThan(nextMonthTop));
  });

  testWidgets('달력 월 새로고침 뒤 매치업은 갱신된 월 일정을 사용한다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final today = kboCivilDateTime();
    final targetMonth = today.month < 3
        ? DateTime(today.year, 3)
        : today.month > 11
        ? DateTime(today.year + 1, 3)
        : DateTime(today.year, today.month);
    final targetDate =
        targetMonth.year == today.year && targetMonth.month == today.month
        ? DateTime(today.year, today.month, today.day)
        : targetMonth;
    final targetYearMonth = _yearMonthKey(targetMonth);
    final monthDelta =
        (targetMonth.year - today.year) * 12 + targetMonth.month - today.month;
    var targetMonthLoads = 0;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          myTeamProvider.overrideWith(() => _FixedMyTeamNotifier('LG')),
          scheduleProvider.overrideWith((_, requestedYearMonth) async {
            if (requestedYearMonth != targetYearMonth) {
              return const [];
            }
            targetMonthLoads += 1;
            final refreshed = targetMonthLoads > 1;
            return [
              ScheduleDay(
                date: _dateKey(targetDate),
                games: [
                  ScheduleGame(
                    gameId: refreshed ? 'refreshed-lg-kt' : 'cached-lg-kt',
                    time: '18:30',
                    awayId: 'LG',
                    awayName: 'LG 트윈스',
                    homeId: 'KT',
                    homeName: 'KT 위즈',
                    stadium: refreshed ? '갱신 후 LG-KT' : '갱신 전 LG-KT',
                  ),
                ],
              ),
            ];
          }),
        ],
        child: const MaterialApp(home: ScheduleScreen()),
      ),
    );
    await tester.pumpAndSettle();

    for (var index = 0; index < monthDelta; index += 1) {
      await tester.tap(find.byIcon(Icons.chevron_right_rounded));
      await tester.pumpAndSettle();
    }

    await tester.tap(find.text('매치업'));
    await tester.pumpAndSettle();

    expect(find.text('갱신 전 LG-KT'), findsOneWidget);
    expect(targetMonthLoads, 1);

    await tester.tap(find.text('내 팀 먼저 보기'));
    await tester.pumpAndSettle();
    final refreshFuture = tester
        .state<RefreshIndicatorState>(find.byType(RefreshIndicator))
        .show();
    await tester.pump();
    await tester.pumpAndSettle();
    await refreshFuture;

    expect(targetMonthLoads, 2);

    await tester.tap(find.text('매치업'));
    await tester.pumpAndSettle();

    expect(find.text('갱신 후 LG-KT'), findsOneWidget);
    expect(find.text('갱신 전 LG-KT'), findsNothing);
  });

  testWidgets('캘린더 영역에서 위로 밀어도 선택일 경기 목록이 스크롤된다', (tester) async {
    final now = kboCivilDateTime();

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

    await tester.drag(find.text('일반 경기'), const Offset(0, -180));
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(firstGame).dy, lessThan(initialTop));
  });

  testWidgets('이미 선택된 일정 탭을 다시 눌러도 선택 월을 유지한다', (tester) async {
    final now = kboCivilDateTime();
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
    final now = kboCivilDateTime();

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

  testWidgets('280px 캘린더 날짜는 44px 터치 영역과 전체 맥락을 읽어 준다', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.binding.setSurfaceSize(const Size(280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final today = kboCivilDateTime();

    try {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            myTeamProvider.overrideWith(() => _FixedMyTeamNotifier('LG')),
            scheduleProvider.overrideWith(
              (_, yearMonth) async => _myTeamScheduleForToday(today, yearMonth),
            ),
          ],
          child: const MaterialApp(home: ScheduleScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('내 팀 우선'), findsOneWidget);
      expect(find.text('내 팀 먼저 보기'), findsNothing);

      final dateCell = find.byKey(
        ValueKey('schedule-date-${today.year}-${today.month}-${today.day}'),
      );
      expect(dateCell, findsOneWidget);
      final size = tester.getSize(dateCell);
      expect(size.width, greaterThanOrEqualTo(44));
      expect(size.height, greaterThanOrEqualTo(44));

      final data = tester.getSemantics(dateCell).getSemanticsData();
      expect(data.label, contains('${today.month}월 ${today.day}일'));
      expect(data.label, contains('오늘'));
      expect(data.label, contains('마이팀 경기 있음'));
      expect(data.label, contains('선택됨'));
      expect(data.flagsCollection.isSelected.toBoolOrNull(), isTrue);
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('마이팀 필터에서 구장별 보기로 전환해도 월 헤더가 화면 안에 남는다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final now = kboCivilDateTime();
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

    await tester.tap(find.text('마이팀만'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('구장별'));
    await tester.pumpAndSettle();

    final monthRect = tester.getRect(find.text(_monthLabel(now)));
    final titleRect = tester.getRect(find.text('일정'));
    final controlsRect = tester.getRect(find.text('내 팀 먼저 보기'));

    expect(monthRect.left, greaterThanOrEqualTo(0));
    expect(monthRect.right, lessThanOrEqualTo(390));
    expect(titleRect.left, greaterThanOrEqualTo(0));
    expect(titleRect.right, lessThanOrEqualTo(390));
    expect(titleRect.bottom, lessThan(controlsRect.top));
    expect(find.byIcon(Icons.chevron_left_rounded), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
    expect(find.byIcon(Icons.today_rounded), findsOneWidget);
    expect(tester.getSize(find.byTooltip('이전 달')), const Size(44, 44));
    expect(tester.getSize(find.byTooltip('다음 달')), const Size(44, 44));
    expect(tester.getSize(find.byTooltip('오늘로 이동')), const Size(44, 44));
  });

  testWidgets('구장별 일정 API 실패는 빈 일정이 아니라 재시도 오류로 구분한다', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          scheduleProvider.overrideWith(
            (_, _) => Future.error('schedule unavailable'),
          ),
        ],
        child: const MaterialApp(home: ScheduleScreen()),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('구장별'));
    await tester.pumpAndSettle();

    expect(find.text('일정을 불러올 수 없습니다'), findsOneWidget);
    expect(find.text('다시 시도'), findsOneWidget);
    expect(find.text('구장별 일정 없음'), findsNothing);
  });

  testWidgets('일정 선택 컨트롤은 선택 상태와 비활성 팀을 semantics로 구분한다', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            myTeamProvider.overrideWith(() => _FixedMyTeamNotifier('LG')),
            scheduleProvider.overrideWith(
              (_, yearMonth) async => _scheduleForMonth(yearMonth),
            ),
            seasonScheduleProvider.overrideWith((_, _) async => const []),
          ],
          child: const MaterialApp(home: ScheduleScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('매치업'));
      await tester.pumpAndSettle();

      final matchupPressable = find.ancestor(
        of: find.text('매치업'),
        matching: find.byType(AppPressable),
      );
      final matchupSemantics = tester
          .getSemantics(matchupPressable)
          .getSemanticsData();
      expect(
        matchupSemantics.flagsCollection.isSelected.toBoolOrNull(),
        isTrue,
      );

      final disabledKtPressable = find.ancestor(
        of: find.text('KT').first,
        matching: find.byType(AppPressable),
      );
      final disabledKtSemantics = tester
          .getSemantics(disabledKtPressable)
          .getSemanticsData();
      expect(
        disabledKtSemantics.flagsCollection.isEnabled.toBoolOrNull(),
        isFalse,
      );
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('일정 경기 상세 진입은 일정 정보로 즉시 이동하고 상세를 뒤에서 갱신한다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final today = kboCivilDateTime();
    final yearMonth = '${today.year}-${today.month.toString().padLeft(2, '0')}';
    const gameId = '20260701SSLG0';
    final detailCompleter = Completer<Game?>();
    final relayCompleter = Completer<RelayData>();
    var detailFetches = 0;
    var relayFetches = 0;
    final router = GoRouter(
      initialLocation: '/schedule',
      routes: [
        GoRoute(
          path: '/schedule',
          builder: (context, state) => const ScheduleScreen(),
        ),
        GoRoute(
          path: '/game/:gameId',
          builder: (context, state) => Text(
            'schedule-detail-${state.pathParameters['gameId']}-${state.uri.queryParameters['tab'] ?? ''}',
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          scheduleProvider.overrideWith((_, month) async {
            if (month != yearMonth) {
              return const <ScheduleDay>[];
            }
            return [
              ScheduleDay(
                date: '$yearMonth-${today.day.toString().padLeft(2, '0')}',
                games: const [
                  ScheduleGame(
                    gameId: gameId,
                    time: '18:30',
                    awayId: 'SS',
                    awayName: '삼성',
                    homeId: 'LG',
                    homeName: 'LG',
                    stadium: '잠실',
                    status: 'LIVE',
                  ),
                ],
              ),
            ];
          }),
          gameProvider.overrideWith((ref, requestedGameId) async {
            detailFetches++;
            return detailCompleter.future;
          }),
          relayDataProvider.overrideWith((ref, requestedGameId) async {
            relayFetches++;
            return relayCompleter.future;
          }),
          gameLineupProvider.overrideWith(
            (ref, requestedGameId) async => const GameLineupData(
              gameId: gameId,
              away: TeamLineupData(teamId: 'SS', lineup: []),
              home: TeamLineupData(teamId: 'LG', lineup: []),
            ),
          ),
          teamPlayersProvider.overrideWith(
            (ref, key) async => const <PlayerProfile>[],
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    await tester.pumpAndSettle();

    final row = find.byKey(const ValueKey('schedule-game-$gameId'));
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    await tester.tap(row);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(detailFetches, 1);
    expect(
      find.byKey(const ValueKey('schedule-game-detail-loading')),
      findsNothing,
    );
    expect(find.text('schedule-detail-$gameId-relay'), findsOneWidget);
    expect(relayFetches, 0);

    detailCompleter.complete(_liveGame(gameId));
    await tester.pump();
    expect(relayCompleter.isCompleted, isFalse);
  });

  testWidgets('일정 경기 상세 진입 refresh 실패 시 live 일정은 중계 탭으로 이동한다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final today = kboCivilDateTime();
    final yearMonth = '${today.year}-${today.month.toString().padLeft(2, '0')}';
    const gameId = '20260701SSLG0';
    final router = _scheduleTestRouter();
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          scheduleProvider.overrideWith(
            (_, month) async => month == yearMonth
                ? _singleScheduleGameForDate(
                    today,
                    const ScheduleGame(
                      gameId: gameId,
                      time: '18:30',
                      awayId: 'SS',
                      awayName: '삼성',
                      homeId: 'LG',
                      homeName: 'LG',
                      stadium: '잠실',
                      status: 'LIVE',
                    ),
                  )
                : const <ScheduleDay>[],
          ),
          gameProvider.overrideWith((ref, requestedGameId) async {
            throw StateError('detail unavailable');
          }),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    await tester.pumpAndSettle();

    final row = find.byKey(const ValueKey('schedule-game-$gameId'));
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    await tester.tap(row);
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('schedule-detail-$gameId-relay'), findsOneWidget);
  });

  testWidgets('일정 live 상세 진입은 미선택 데이터와 선수 이미지를 미리 요청하지 않는다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final today = kboCivilDateTime();
    final yearMonth = '${today.year}-${today.month.toString().padLeft(2, '0')}';
    const gameId = '20260701SSLG0';
    final relayCompleter = Completer<RelayData>();
    final lineupCompleter = Completer<GameLineupData>();
    var teamPlayerFetches = 0;
    final router = _scheduleTestRouter();
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          scheduleProvider.overrideWith(
            (_, month) async => month == yearMonth
                ? _singleScheduleGameForDate(
                    today,
                    const ScheduleGame(
                      gameId: gameId,
                      time: '18:30',
                      awayId: 'SS',
                      awayName: '삼성',
                      homeId: 'LG',
                      homeName: 'LG',
                      stadium: '잠실',
                      status: 'LIVE',
                    ),
                  )
                : const <ScheduleDay>[],
          ),
          gameProvider.overrideWith(
            (ref, requestedGameId) async => _liveGame(gameId),
          ),
          relayDataProvider.overrideWith((ref, requestedGameId) async {
            return relayCompleter.future;
          }),
          gameLineupProvider.overrideWith((ref, requestedGameId) async {
            return lineupCompleter.future;
          }),
          teamPlayersProvider.overrideWith((ref, key) async {
            teamPlayerFetches++;
            return const <PlayerProfile>[];
          }),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    await tester.pumpAndSettle();

    final row = find.byKey(const ValueKey('schedule-game-$gameId'));
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    await tester.tap(row);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(
      find.byKey(const ValueKey('schedule-game-detail-loading')),
      findsNothing,
    );
    expect(find.text('schedule-detail-$gameId-relay'), findsOneWidget);
    expect(teamPlayerFetches, 0);
    expect(lineupCompleter.isCompleted, isFalse);
    expect(relayCompleter.isCompleted, isFalse);
    expect(lineupCompleter.isCompleted, isFalse);
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

GoRouter _scheduleTestRouter() {
  return GoRouter(
    initialLocation: '/schedule',
    routes: [
      GoRoute(
        path: '/schedule',
        builder: (context, state) => const ScheduleScreen(),
      ),
      GoRoute(
        path: '/game/:gameId',
        builder: (context, state) => Text(
          'schedule-detail-${state.pathParameters['gameId']}-${state.uri.queryParameters['tab'] ?? ''}',
        ),
      ),
    ],
  );
}

List<ScheduleDay> _singleScheduleGameForDate(DateTime date, ScheduleGame game) {
  final yearMonth = '${date.year}-${date.month.toString().padLeft(2, '0')}';
  return [
    ScheduleDay(
      date: '$yearMonth-${date.day.toString().padLeft(2, '0')}',
      games: [game],
    ),
  ];
}

Game _liveGame(String gameId) {
  return Game(
    gameId: gameId,
    status: GameStatus.live,
    inning: '7회초',
    away: const TeamScore(
      teamId: 'SS',
      teamName: '삼성',
      shortName: '삼성',
      score: 3,
      innings: [],
    ),
    home: const TeamScore(
      teamId: 'LG',
      teamName: 'LG',
      shortName: 'LG',
      score: 2,
      innings: [],
    ),
    stadium: '잠실',
    startTime: '18:30',
  );
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

  final today = kboCivilDateTime().day.toString().padLeft(2, '0');
  return [
    ScheduleDay(
      date: '$requestedYearMonth-$today',
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
      date: '$requestedYearMonth-$today',
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
      ScheduleGame(
        gameId: 'today-live-lg-kt',
        time: '18:31',
        awayId: 'LG',
        awayName: 'LG 트윈스',
        homeId: 'KT',
        homeName: 'KT 위즈',
        stadium: '오늘 진행 중 LG-KT',
        status: 'LIVE',
        awayScore: 2,
        homeScore: 1,
      ),
      ScheduleGame(
        gameId: 'today-final-lg-kt',
        time: '18:32',
        awayId: 'LG',
        awayName: 'LG 트윈스',
        homeId: 'KT',
        homeName: 'KT 위즈',
        stadium: '오늘 종료 LG-KT',
        status: 'FINAL',
        awayScore: 3,
        homeScore: 1,
      ),
      ScheduleGame(
        gameId: 'today-cancelled-lg-kt',
        time: '18:33',
        awayId: 'LG',
        awayName: 'LG 트윈스',
        homeId: 'KT',
        homeName: 'KT 위즈',
        stadium: '오늘 취소 LG-KT',
        status: 'CANCELLED',
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
