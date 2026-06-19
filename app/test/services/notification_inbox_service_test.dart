import 'package:flutter_test/flutter_test.dart';
import 'package:kbo_fans/services/notification_inbox_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'push inbox stores latest entries in reverse chronological order',
    () async {
      final service = NotificationInboxService.instance;

      await service.addPush(
        messageId: 'old',
        title: '경기 시작',
        body: 'LG vs KT 18:30',
        data: const {'type': 'game_start', 'gameId': '20260619KTLG0'},
        route: '/game/20260619KTLG0?tab=relay',
        source: 'foreground',
        read: false,
        receivedAt: DateTime(2026, 6, 19, 18, 20),
      );
      await service.addPush(
        messageId: 'new',
        title: '득점 장면',
        body: '7회말 LG 득점',
        data: const {'type': 'scoring', 'gameId': '20260619KTLG0'},
        route: '/game/20260619KTLG0?tab=relay',
        source: 'foreground',
        read: false,
        receivedAt: DateTime(2026, 6, 19, 19, 42),
      );

      final entries = await service.loadEntries();

      expect(entries.map((entry) => entry.id), ['new', 'old']);
      expect(entries.first.title, '득점 장면');
      expect(entries.first.read, isFalse);
    },
  );

  test(
    'push inbox merges duplicate message ids and preserves read state',
    () async {
      final service = NotificationInboxService.instance;

      await service.addPush(
        messageId: 'same-message',
        title: '홈런',
        body: '문보경 홈런',
        data: const {'type': 'homerun', 'gameId': '20260619KTLG0'},
        route: '/game/20260619KTLG0?tab=relay',
        source: 'background',
        read: false,
        receivedAt: DateTime(2026, 6, 19, 20, 1),
      );
      await service.addPush(
        messageId: 'same-message',
        title: '홈런',
        body: '문보경 홈런',
        data: const {'type': 'homerun', 'gameId': '20260619KTLG0'},
        route: '/game/20260619KTLG0?tab=relay',
        source: 'opened',
        read: true,
        receivedAt: DateTime(2026, 6, 19, 20, 2),
      );

      final entries = await service.loadEntries();

      expect(entries, hasLength(1));
      expect(entries.single.read, isTrue);
      expect(entries.single.source, 'opened');
    },
  );

  test('push inbox caps stored entries to fifty', () async {
    final service = NotificationInboxService.instance;

    for (var index = 0; index < 55; index += 1) {
      await service.addPush(
        messageId: 'message-$index',
        title: '푸시 $index',
        body: '본문 $index',
        data: const {'type': 'baseball_info'},
        route: '/home',
        source: 'foreground',
        read: false,
        receivedAt: DateTime(2026, 6, 19, 12, index),
      );
    }

    final entries = await service.loadEntries();

    expect(entries, hasLength(50));
    expect(entries.first.id, 'message-54');
    expect(entries.last.id, 'message-5');
  });
}
