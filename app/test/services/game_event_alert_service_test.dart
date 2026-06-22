import 'package:flutter_test/flutter_test.dart';
import 'package:kbo_fans/services/game_event_alert_service.dart';

void main() {
  test('로컬 경기 이벤트 알림은 local native 또는 명시 플래그에서만 처리한다', () {
    expect(
      shouldProcessLocalGameEventAlerts(
        isWeb: false,
        isLocal: true,
        forceEnabled: false,
      ),
      isTrue,
    );
    expect(
      shouldProcessLocalGameEventAlerts(
        isWeb: false,
        isLocal: false,
        forceEnabled: false,
      ),
      isFalse,
    );
    expect(
      shouldProcessLocalGameEventAlerts(
        isWeb: false,
        isLocal: false,
        forceEnabled: true,
      ),
      isTrue,
    );
    expect(
      shouldProcessLocalGameEventAlerts(
        isWeb: true,
        isLocal: true,
        forceEnabled: true,
      ),
      isFalse,
    );
  });
}
