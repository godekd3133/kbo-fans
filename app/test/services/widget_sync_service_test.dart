import 'package:flutter_test/flutter_test.dart';
import 'package:kbo_fans/services/widget_sync_service.dart';

void main() {
  group('widget my team storage', () {
    test('encodes missing my team as an empty property-list-safe string', () {
      expect(encodeWidgetMyTeamIdForStorage(null), '');
    });

    test('decodes missing stored my team values back to null', () {
      expect(decodeWidgetMyTeamIdFromStorage(null), isNull);
      expect(decodeWidgetMyTeamIdFromStorage(''), isNull);
    });

    test('preserves selected my team ids', () {
      expect(encodeWidgetMyTeamIdForStorage('LG'), 'LG');
      expect(decodeWidgetMyTeamIdFromStorage('LG'), 'LG');
    });
  });
}
