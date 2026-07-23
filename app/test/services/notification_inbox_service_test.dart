import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kbo_fans/services/notification_inbox_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
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

  test(
    'stable backend event id deduplicates retries with different message ids',
    () async {
      final service = NotificationInboxService.instance;

      await service.addPush(
        messageId: 'fcm-attempt-1',
        title: '득점',
        body: 'LG 3:2 KT',
        data: const {
          'eventId': 'scoreboard|20260619KTLG0|2:2|3:2',
          'type': 'scoring',
          'gameId': '20260619KTLG0',
        },
        route: '/game/20260619KTLG0?tab=relay',
        source: 'background',
        read: false,
        receivedAt: DateTime(2026, 6, 19, 20, 1),
      );
      await service.addPush(
        messageId: 'fcm-attempt-2',
        title: '득점',
        body: 'LG 3:2 KT',
        data: const {
          'eventId': 'scoreboard|20260619KTLG0|2:2|3:2',
          'type': 'scoring',
          'gameId': '20260619KTLG0',
        },
        route: '/game/20260619KTLG0?tab=relay',
        source: 'opened',
        read: true,
        receivedAt: DateTime(2026, 6, 19, 20, 2),
      );

      final entries = await service.loadEntries();

      expect(entries, hasLength(1));
      expect(entries.single.id, 'scoreboard|20260619KTLG0|2:2|3:2');
      expect(entries.single.source, 'opened');
      expect(entries.single.read, isTrue);
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

  test('push inbox ignores malformed stored payloads', () async {
    SharedPreferences.setMockInitialValues({
      NotificationInboxService.storageKey: 'not-json',
    });
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.withData({
          NotificationInboxService.storageKey: 'not-json',
        });

    final entries = await NotificationInboxService.instance.loadEntries();

    expect(entries, isEmpty);
  });

  test(
    'legacy inbox list migrates into isolate-safe per-entry storage',
    () async {
      SharedPreferences.setMockInitialValues({
        NotificationInboxService.storageKey: jsonEncode([
          {
            'id': 'legacy-message',
            'title': '기존 알림',
            'body': '업데이트 전 수신',
            'type': 'game_end',
            'route': '/home',
            'gameId': '',
            'teamId': 'LG',
            'source': 'background',
            'receivedAt': DateTime(2026, 6, 19, 21).toIso8601String(),
            'read': true,
          },
        ]),
      });

      final entries = await NotificationInboxService.instance.loadEntries();
      final legacyPrefs = await SharedPreferences.getInstance();

      expect(entries, hasLength(1));
      expect(entries.single.id, 'legacy-message');
      expect(entries.single.read, isTrue);
      expect(
        legacyPrefs.containsKey(NotificationInboxService.storageKey),
        isFalse,
      );
    },
  );

  test(
    'push inbox keeps concurrent different messages without lost updates',
    () async {
      final service = NotificationInboxService.instance;

      await Future.wait([
        for (var index = 0; index < 100; index += 1)
          service.addPush(
            messageId: 'concurrent-$index',
            title: '동시 푸시 $index',
            body: '본문 $index',
            data: const {'type': 'scoring'},
            route: '/home',
            source: index.isEven ? 'foreground' : 'background',
            read: false,
            receivedAt: DateTime(2026, 6, 20).add(Duration(seconds: index)),
          ),
      ]);

      final entries = await service.loadEntries();

      expect(entries, hasLength(50));
      expect(entries.map((entry) => entry.id).toSet(), hasLength(50));
      expect(entries.first.id, 'concurrent-99');
      expect(entries.last.id, 'concurrent-50');
    },
  );

  test(
    'read receipt never regresses during a concurrent duplicate upsert',
    () async {
      final service = NotificationInboxService.instance;
      await service.addPush(
        messageId: 'same-concurrent-message',
        title: '득점',
        body: 'LG 득점',
        data: const {'type': 'scoring'},
        route: '/home',
        source: 'foreground',
        read: false,
        receivedAt: DateTime(2026, 6, 20, 18, 30),
      );

      await Future.wait([
        service.markRead('same-concurrent-message'),
        service.addPush(
          messageId: 'same-concurrent-message',
          title: '득점',
          body: 'LG 득점',
          data: const {'type': 'scoring'},
          route: '/home',
          source: 'background',
          read: false,
          receivedAt: DateTime(2026, 6, 20, 18, 31),
        ),
      ]);

      final entries = await service.loadEntries();

      expect(entries, hasLength(1));
      expect(entries.single.read, isTrue);
      expect(entries.single.source, 'background');
    },
  );
}
