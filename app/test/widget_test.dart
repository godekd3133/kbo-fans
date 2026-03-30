import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kbo_fans/core/config/app_config.dart';
import 'package:kbo_fans/main.dart';

void main() {
  testWidgets('앱 루트가 렌더링된다', (WidgetTester tester) async {
    AppConfig.initialize();

    await tester.pumpWidget(
      const ProviderScope(
        child: KboFansApp(showOnboarding: false),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('KBO Fans'), findsOneWidget);
  });
}
