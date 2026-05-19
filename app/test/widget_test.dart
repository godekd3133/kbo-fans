import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kbo_fans/core/config/app_config.dart';
import 'package:kbo_fans/core/widgets/dev_console.dart';
import 'package:kbo_fans/main.dart';

void main() {
  testWidgets('앱 루트가 렌더링된다', (WidgetTester tester) async {
    AppConfig.initialize();
    SharedPreferences.setMockInitialValues({'onboardingDone': false});

    await tester.pumpWidget(const ProviderScope(child: KboFansApp()));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(DevConsoleOverlay), findsOneWidget);
  });
}
