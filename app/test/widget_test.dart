import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kbo_fans/core/config/app_config.dart';
import 'package:kbo_fans/core/router/app_router.dart';
import 'package:kbo_fans/core/widgets/dev_console.dart';
import 'package:kbo_fans/main.dart';

void main() {
  testWidgets('앱 루트가 렌더링된다', (WidgetTester tester) async {
    AppConfig.initialize();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          onboardingDoneProvider.overrideWithValue(true),
        ],
        child: const KboFansApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(DevConsoleOverlay), findsOneWidget);
  });
}
