import 'package:flutter_test/flutter_test.dart';

import 'package:kbo_fans/services/push_notification_service.dart';

void main() {
  test('device self-test payload carries the public installation owner', () {
    expect(
      buildPushDeviceTestPayload(
        deviceToken: 'fcm-token',
        installationId: 'installation-owner',
      ),
      {'deviceToken': 'fcm-token', 'installationId': 'installation-owner'},
    );
  });

  test(
    'push receipt payload carries the exact registered installation owner',
    () {
      final payload = buildPushReceiptPayload(
        deviceToken: 'fcm-token',
        installationId: 'installation-owner',
        messageId: 'message-1',
        source: 'foreground',
        route: '/home',
        receivedAt: DateTime.utc(2026, 8, 10),
        data: const {'type': 'test_push'},
      );

      expect(payload['installationId'], 'installation-owner');
    },
  );
}
