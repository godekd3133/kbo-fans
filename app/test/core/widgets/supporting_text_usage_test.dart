import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kbo_fans/core/bootstrap/startup_prep_state.dart';
import 'package:kbo_fans/core/config/app_config.dart';
import 'package:kbo_fans/core/theme/app_theme.dart';
import 'package:kbo_fans/core/widgets/boot_splash_screen.dart';
import 'package:kbo_fans/core/widgets/dev_console.dart';
import 'package:kbo_fans/core/widgets/game_status_badge.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  AppConfig.initialize();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    DevConsole.instance.clear();
  });

  testWidgets('부트 진행 단계는 읽을 수 있는 지원 텍스트를 쓴다', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          startupPrepProvider.overrideWith(_TwoStepStartupNotifier.new),
        ],
        child: MaterialApp(
          theme: AppTheme.dark,
          home: const BootSplashScreen(),
        ),
      ),
    );
    await tester.pump();

    expect(
      tester.widget<Text>(find.text('0/2 단계')).style?.color,
      AppTheme.darkColors.textSupporting,
    );
  });

  testWidgets('취소 경기 배지는 disabled가 아닌 상태 정보로 표시한다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: GameStatusBadge.forSchedule('CANCELLED', statusLabel: '우천취소'),
        ),
      ),
    );

    expect(
      tester.widget<Text>(find.text('우천취소')).style?.color,
      AppTheme.darkColors.textSupporting,
    );
  });

  testWidgets('개발자 콘솔의 비선택 필터와 빈 상태는 supporting으로 남는다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: const DevConsoleOverlay(child: Scaffold()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.terminal));
    await tester.pumpAndSettle();

    expect(
      tester
          .widgetList<Text>(find.text('API'))
          .every(
            (text) => text.style?.color == AppTheme.darkColors.textSupporting,
          ),
      isTrue,
    );
    expect(
      tester.widget<Text>(find.text('표시할 로그가 없습니다')).style?.color,
      AppTheme.darkColors.textSupporting,
    );
    expect(
      tester.widget<Icon>(find.byIcon(Icons.close)).color,
      AppTheme.darkColors.textSupporting,
    );
  });
}

class _TwoStepStartupNotifier extends StartupPrepNotifier {
  @override
  StartupPrepState build() => const StartupPrepState(
    title: 'KBO Fans',
    message: '야구 정보를 준비하는 중입니다',
    completedSteps: 0,
    totalSteps: 2,
    blocking: true,
  );
}
