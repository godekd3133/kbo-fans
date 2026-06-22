import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kbo_fans/core/theme/app_theme.dart';
import 'package:kbo_fans/features/settings/settings_screen.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'KBO Fans',
      packageName: 'com.kbofans.app',
      version: '0.1.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  testWidgets('더보기 허브는 마이팀과 오늘 정보 섹션을 보여준다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(theme: AppTheme.dark, home: const SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('KBO 팬 허브'), findsOneWidget);
    expect(find.text('마이팀을 선택하세요'), findsOneWidget);
    expect(find.text('오늘 챙길 정보'), findsOneWidget);
    expect(find.text('현재 프리셋: 내 팀 집중'), findsNothing);
    expect(find.text('알림 플레이북'), findsNothing);
    expect(find.text('리그 전체 알림'), findsNothing);
    expect(find.text('프리셋 적용'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('빠른 이동'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('빠른 이동'), findsOneWidget);
  });

  testWidgets('앱 밖 표면 설명은 사용자 언어로 보인다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(theme: AppTheme.dark, home: const SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    final mainScroll = find.byType(Scrollable).first;

    await tester.scrollUntilVisible(
      find.text('앱 밖 표면'),
      500,
      scrollable: mainScroll,
    );
    expect(find.text('푸시'), findsOneWidget);
    expect(find.text('라이브 액티비티'), findsOneWidget);
    expect(find.text('브리프'), findsOneWidget);
  });

  testWidgets('저장된 커스텀 알림 설정이 있어도 플레이북 UI를 노출하지 않는다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({
      'push_notifications.scoring.delivery': 'off',
    });

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(theme: AppTheme.dark, home: const SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('KBO 팬 허브'), findsOneWidget);
    expect(find.text('현재 프리셋: 커스텀'), findsNothing);
    expect(find.text('알림 플레이북'), findsNothing);
    expect(find.text('프리셋 적용'), findsNothing);
  });

  testWidgets('앱 정보 및 지원 항목이 실제 동작한다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(theme: AppTheme.dark, home: const SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    final mainScroll = find.byType(Scrollable).first;

    await tester.scrollUntilVisible(
      find.text('세부 설정 및 지원'),
      500,
      scrollable: mainScroll,
    );

    expect(find.text('0.1.0+1'), findsOneWidget);
    expect(find.text('업데이트 소식'), findsOneWidget);
    expect(find.text('문의하기'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('이용약관'),
      200,
      scrollable: mainScroll,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('이용약관'));
    await tester.pumpAndSettle();
    expect(find.text('서비스 이용약관'), findsOneWidget);
    expect(find.text('서비스 성격'), findsOneWidget);

    await tester.tap(find.byTooltip('닫기'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('개인정보처리방침'),
      200,
      scrollable: mainScroll,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('개인정보처리방침'));
    await tester.pumpAndSettle();
    expect(find.text('개인정보처리방침'), findsWidgets);
    expect(find.text('수집하는 정보'), findsOneWidget);

    await tester.tap(find.byTooltip('닫기'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('오픈소스 라이선스'),
      200,
      scrollable: mainScroll,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('오픈소스 라이선스'));
    await tester.pumpAndSettle();
    expect(find.byType(LicensePage), findsOneWidget);
  });
}
