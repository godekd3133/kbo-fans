import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kbo_fans/services/live_activity_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('Android notification stop action clears followed game', () async {
    await LiveActivityService.instance.followGame('20260520LGKT0');

    await LiveActivityService.handleAndroidNotificationResponseForTesting(
      const NotificationResponse(
        notificationResponseType:
            NotificationResponseType.selectedNotificationAction,
        actionId: 'stop_following_game',
      ),
    );

    expect(await LiveActivityService.instance.followedGameId(), isNull);
  });

  test('other Android notification actions keep followed game', () async {
    await LiveActivityService.instance.followGame('20260520LGKT0');

    await LiveActivityService.handleAndroidNotificationResponseForTesting(
      const NotificationResponse(
        notificationResponseType: NotificationResponseType.selectedNotification,
      ),
    );

    expect(
      await LiveActivityService.instance.followedGameId(),
      '20260520LGKT0',
    );
  });
}
