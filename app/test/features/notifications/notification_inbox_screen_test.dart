import '../../helpers/metadata_finder.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kbo_fans/core/theme/app_theme.dart';
import 'package:kbo_fans/core/widgets/app_motion.dart';
import 'package:kbo_fans/core/widgets/main_scaffold.dart';
import 'package:kbo_fans/features/notifications/notification_inbox_screen.dart';
import 'package:kbo_fans/features/settings/settings_screen.dart';
import 'package:kbo_fans/services/notification_inbox_service.dart';
import 'package:kbo_fans/services/push_notification_service.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    PackageInfo.setMockInitialValues(
      appName: 'KBO Fans',
      packageName: 'com.kbofans.app',
      version: '0.1.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  testWidgets('renders stored push notifications as an inbox timeline', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await NotificationInboxService.instance.addPush(
      messageId: 'score-push',
      title: '득점 장면',
      body: '7회말 문보경 우전 적시타 · 현재 4:3',
      data: const {'type': 'scoring', 'gameId': '20260619SSLG0'},
      route: '/game/20260619SSLG0?tab=relay',
      source: 'foreground',
      read: false,
      receivedAt: DateTime(2026, 6, 19, 20, 12),
    );

    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.dark, home: const NotificationInboxScreen()),
    );
    await tester.pumpAndSettle();

    expect(find.text('알림함'), findsOneWidget);
    expect(find.text('푸시 알림'), findsNothing);
    expect(find.text('득점 장면'), findsOneWidget);
    expect(metadataText('7회말 문보경 우전 적시타 · 현재 4:3'), findsOneWidget);
    expect(find.text('새 알림'), findsOneWidget);
    expect(
      tester.widget<Icon>(find.byIcon(Icons.chevron_right_rounded)).color,
      AppTheme.darkColors.textSupporting,
    );
  });

  testWidgets('동시 inbox refresh는 목록과 설정 loader를 중복 호출하지 않는다', (tester) async {
    final entriesResult = Completer<List<NotificationInboxEntry>>();
    final settingsResult = Completer<PushNotificationSettings>();
    var entriesCalls = 0;
    var settingsCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: NotificationInboxScreen(
          entriesLoader: () {
            entriesCalls += 1;
            return entriesResult.future;
          },
          settingsLoader: () {
            settingsCalls += 1;
            return settingsResult.future;
          },
        ),
      ),
    );
    await tester.pump();

    final refresh = tester
        .widget<RefreshIndicator>(find.byType(RefreshIndicator))
        .onRefresh();
    await tester.pump();

    expect(entriesCalls, 1);
    expect(settingsCalls, 1);

    entriesResult.complete(const <NotificationInboxEntry>[]);
    settingsResult.complete(const PushNotificationSettings.defaults());
    await refresh;
    await tester.pumpAndSettle();

    expect(find.text('아직 받은 알림이 없어요'), findsOneWidget);
  });

  testWidgets(
    'shows the recent-50 contract and updates the visible filter count',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        await tester.binding.setSurfaceSize(const Size(390, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final entries = [
          _entry(
            id: 'unread-game',
            title: '새 득점',
            type: 'scoring',
            read: false,
          ),
          _entry(
            id: 'read-brief',
            title: '읽은 브리프',
            type: 'baseball_info',
            read: true,
          ),
        ];

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark,
            home: NotificationInboxScreen(
              entriesLoader: () async => entries,
              settingsLoader: () async =>
                  const PushNotificationSettings.defaults(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('최근 알림 보관함'), findsNothing);
        expect(find.text('보관 안내'), findsOneWidget);
        expect(find.text('오늘 놓치지 않은 신호'), findsNothing);
        expect(find.text('안 읽은 알림 1개'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('inbox-storage-info')));
        await tester.pumpAndSettle();
        expect(find.textContaining('최대 50개 보관'), findsOneWidget);
        await tester.tap(find.text('닫기'));
        await tester.pumpAndSettle();

        final allFilter = find.ancestor(
          of: find.text('전체'),
          matching: find.byType(AppPressable),
        );
        final unreadFilter = find.ancestor(
          of: find.text('안 읽음'),
          matching: find.byType(AppPressable),
        );
        expect(tester.getSize(allFilter).height, greaterThanOrEqualTo(44));
        expect(tester.getSize(unreadFilter).height, greaterThanOrEqualTo(44));
        expect(
          tester
              .getSemantics(find.text('전체'))
              .getSemanticsData()
              .flagsCollection
              .isSelected
              .toBoolOrNull(),
          isTrue,
        );

        final unreadFocusOutline = find.descendant(
          of: unreadFilter,
          matching: find.byKey(const ValueKey('app-pressable-focus-outline')),
        );
        Focus.of(tester.element(unreadFocusOutline)).requestFocus();
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();

        expect(find.text('안 읽은 알림 1개'), findsOneWidget);
        expect(find.text('읽은 브리프'), findsNothing);
        expect(
          tester
              .getSemantics(
                find.descendant(of: unreadFilter, matching: find.text('안 읽음')),
              )
              .getSemanticsData()
              .flagsCollection
              .isSelected
              .toBoolOrNull(),
          isTrue,
        );
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets('320px 240% 알림 요약은 수치와 설명을 줄임표 없이 재배치한다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2.4)),
          child: child ?? const SizedBox.shrink(),
        ),
        home: NotificationInboxScreen(
          entriesLoader: () async => [
            _entry(
              id: 'large-text-entry',
              title: '연장전 득점 알림',
              type: 'scoring',
              read: false,
            ),
          ],
          settingsLoader: () async => const PushNotificationSettings.defaults(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('안 읽은 알림 1개'), findsOneWidget);
    expect(find.text('보관'), findsNothing);
    expect(find.text('현재 표시'), findsNothing);
    expect(
      tester.getSize(find.byKey(const ValueKey('inbox-storage-info'))).height,
      greaterThanOrEqualTo(44),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty inbox is distinct from a load failure', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: NotificationInboxScreen(
          entriesLoader: () async => const <NotificationInboxEntry>[],
          settingsLoader: () async => const PushNotificationSettings.defaults(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('안 읽은 알림 0개'), findsNothing);
    expect(find.text('모두 읽음'), findsNothing);
    expect(find.text('아직 받은 알림이 없어요'), findsOneWidget);
    expect(find.text('최근 알림을 불러오지 못했습니다'), findsNothing);
    expect(find.text('알림 설정을 확인할 수 없습니다. 알림 목록은 그대로 유지됩니다.'), findsNothing);
  });

  testWidgets(
    'entry load failure keeps loaded settings and can retry separately',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var entryAttempts = 0;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: NotificationInboxScreen(
            entriesLoader: () async {
              entryAttempts += 1;
              if (entryAttempts == 1) {
                throw StateError('entries unavailable');
              }
              return [
                _entry(
                  id: 'recovered-entry',
                  title: '복구된 알림',
                  type: 'scoring',
                  read: false,
                ),
              ];
            },
            settingsLoader: () async =>
                const PushNotificationSettings.defaults(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _openNotificationOptions(tester);

      expect(find.text('최근 알림을 불러오지 못했습니다'), findsOneWidget);
      expect(find.text('아직 받은 알림이 없어요'), findsNothing);
      expect(find.text('경기 시작'), findsOneWidget);
      expect(find.text('보관 안내'), findsOneWidget);
      expect(find.text('확인 불가'), findsNothing);
      expect(find.text('정리됨'), findsNothing);

      await tester.tap(find.text('알림 목록 다시 시도'));
      await tester.pumpAndSettle();

      expect(entryAttempts, 2);
      expect(find.text('복구된 알림'), findsOneWidget);
      expect(find.text('최근 알림을 불러오지 못했습니다'), findsNothing);
      expect(find.text('안 읽은 알림 1개'), findsOneWidget);
    },
  );

  testWidgets('settings load failure keeps entries and can retry separately', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var settingsAttempts = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: NotificationInboxScreen(
          entriesLoader: () async => [
            _entry(
              id: 'preserved-entry',
              title: '유지된 알림',
              type: 'scoring',
              read: false,
            ),
          ],
          settingsLoader: () async {
            settingsAttempts += 1;
            if (settingsAttempts == 1) {
              throw StateError('settings unavailable');
            }
            return const PushNotificationSettings.defaults();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _openNotificationOptions(tester);

    expect(find.text('유지된 알림'), findsOneWidget);
    expect(find.text('안 읽은 알림 1개'), findsOneWidget);
    expect(find.text('알림 설정을 확인할 수 없습니다. 알림 목록은 그대로 유지됩니다.'), findsOneWidget);
    expect(find.text('최근 알림을 불러오지 못했습니다'), findsNothing);

    await tester.scrollUntilVisible(
      find.text('알림 설정 다시 시도'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('알림 설정 다시 시도'));
    await tester.pumpAndSettle();

    expect(settingsAttempts, 2);
    expect(find.text('알림 설정을 확인할 수 없습니다. 알림 목록은 그대로 유지됩니다.'), findsNothing);
    expect(find.text('경기 시작'), findsOneWidget);
    expect(find.text('유지된 알림'), findsOneWidget);
  });

  testWidgets('marks all stored notifications as read', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await NotificationInboxService.instance.addPush(
      messageId: 'brief-push',
      title: '월요일 야구 체크',
      body: '이번 주 KBO 일정과 순위 흐름을 확인해 보세요.',
      data: const {'type': 'baseball_info'},
      route: '/home',
      source: 'foreground',
      read: false,
      receivedAt: DateTime(2026, 6, 19, 9, 0),
    );

    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.dark, home: const NotificationInboxScreen()),
    );
    await tester.pumpAndSettle();

    expect(find.text('새 알림'), findsOneWidget);

    await tester.tap(find.text('모두 읽음'));
    await tester.pumpAndSettle();

    expect(find.text('정리됨'), findsNothing);
    expect(find.text('모두 읽음'), findsNothing);
    expect(find.text('새 알림'), findsNothing);
  });

  testWidgets('잘못된 알림 연결은 목록을 유지하고 읽음 처리와 안내를 제공한다', (tester) async {
    var read = false;
    final router = GoRouter(
      initialLocation: '/notifications',
      routes: [
        GoRoute(
          path: '/notifications',
          builder: (_, _) => NotificationInboxScreen(
            entriesLoader: () async => [
              _entry(
                id: 'broken',
                title: '예전 경기 알림',
                type: 'scoring',
                read: false,
                route: '/unsupported-notification',
              ),
            ],
            settingsLoader: () async =>
                const PushNotificationSettings.defaults(),
            markRead: (_) async {
              read = true;
            },
          ),
        ),
        GoRoute(
          path: '/home',
          builder: (_, _) => const Scaffold(body: Text('홈 도착')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('예전 경기 알림'));
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/notifications');
    expect(find.text('예전 경기 알림'), findsOneWidget);
    expect(find.text('이 알림의 연결 정보를 찾을 수 없어요.'), findsOneWidget);
    expect(read, isTrue);
    expect(find.text('홈 도착'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('읽음 저장 실패가 알림 deep link 이동을 막지 않는다', (tester) async {
    var markReadAttempted = false;
    final router = GoRouter(
      initialLocation: '/notifications',
      routes: [
        GoRoute(
          path: '/notifications',
          builder: (_, _) => NotificationInboxScreen(
            entriesLoader: () async => [
              _entry(
                id: 'route-entry',
                title: '경기 상세 열기',
                type: 'scoring',
                read: false,
                route: '/home',
              ),
            ],
            settingsLoader: () async =>
                const PushNotificationSettings.defaults(),
            markRead: (_) async {
              markReadAttempted = true;
              throw StateError('storage unavailable');
            },
          ),
        ),
        GoRoute(
          path: '/home',
          builder: (_, _) => const Scaffold(body: Text('홈 도착')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('경기 상세 열기'));
    await tester.pumpAndSettle();

    expect(markReadAttempted, isTrue);
    expect(find.text('홈 도착'), findsOneWidget);
  });

  testWidgets('inbox settings link returns to the settings tab body', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: '/notifications',
      routes: [
        ShellRoute(
          builder: (context, state, child) => MainScaffold(child: child),
          routes: [
            GoRoute(
              path: '/settings',
              builder: (_, _) => const SettingsScreen(),
            ),
          ],
        ),
        GoRoute(
          path: '/notifications',
          builder: (_, _) => const NotificationInboxScreen(),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    await _openNotificationOptions(tester);

    expect(find.text('알림함'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('설정'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('설정'));
    await tester.pumpAndSettle();

    expect(router.routerDelegate.currentConfiguration.uri.path, '/settings');
    expect(find.text('마이팀을 선택하세요'), findsOneWidget);
    expect(find.text('경기 중'), findsOneWidget);
    expect(find.text('경기 중 실시간 알림받기'), findsNothing);
  });
}

NotificationInboxEntry _entry({
  required String id,
  required String title,
  required String type,
  required bool read,
  String route = '',
}) {
  return NotificationInboxEntry(
    id: id,
    title: title,
    body: '$title 본문',
    type: type,
    route: route,
    gameId: '',
    teamId: '',
    source: 'test',
    receivedAt: DateTime(2026, 7, 23, 18),
    read: read,
  );
}

Future<void> _openNotificationOptions(WidgetTester tester) async {
  final options = find.byKey(const ValueKey('inbox-notification-options'));
  await tester.ensureVisible(options);
  await tester.tap(find.text('알림 종류'));
  await tester.pumpAndSettle();
}
