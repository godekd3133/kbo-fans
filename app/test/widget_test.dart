import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kbo_fans/core/config/app_config.dart';
import 'package:kbo_fans/core/widgets/dev_console.dart';
import 'package:kbo_fans/data/providers.dart';
import 'package:kbo_fans/features/records/records_screen.dart';
import 'package:kbo_fans/main.dart';

void main() {
  testWidgets('앱 루트가 렌더링된다', (WidgetTester tester) async {
    AppConfig.initialize();
    SharedPreferences.setMockInitialValues({'onboardingDone': false});

    await tester.pumpWidget(const ProviderScope(child: KboFansApp()));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(DevConsoleOverlay), findsOneWidget);
  });

  testWidgets('기록실 리그 요약 오류를 숨기지 않는다', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          recordsOverviewProvider.overrideWith((ref, season) {
            throw Exception('offline');
          }),
        ],
        child: const MaterialApp(home: RecordsScreen()),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('리그 기록을 불러올 수 없습니다'), findsOneWidget);
    expect(find.text('데이터를 불러오지 못했습니다. 잠시 후 다시 시도해주세요.'), findsOneWidget);
  });
}
