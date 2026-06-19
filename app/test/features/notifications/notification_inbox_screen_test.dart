import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kbo_fans/core/theme/app_theme.dart';
import 'package:kbo_fans/features/notifications/notification_inbox_screen.dart';
import 'package:kbo_fans/services/notification_inbox_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
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
    expect(find.text('득점 장면'), findsOneWidget);
    expect(find.text('7회말 문보경 우전 적시타 · 현재 4:3'), findsOneWidget);
    expect(find.text('새 알림'), findsOneWidget);
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

    expect(find.text('정리됨'), findsOneWidget);
    expect(find.text('새 알림'), findsNothing);
  });
}
