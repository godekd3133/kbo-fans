import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kbo_fans/core/theme/app_theme.dart';
import 'package:kbo_fans/core/theme/theme_mode_controller.dart';
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

  testWidgets('설정 허브는 필수 액션만 보여주고 다른 탭 정보를 중복 노출하지 않는다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(theme: AppTheme.dark, home: const SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('설정'), findsOneWidget);
    expect(find.text('마이팀을 선택하세요'), findsOneWidget);
    expect(find.text('마이팀 선택'), findsOneWidget);
    expect(find.text('오늘 챙길 정보'), findsNothing);
    expect(find.text('경기 있음'), findsNothing);
    expect(find.text('최근'), findsNothing);
    expect(find.text('앱 밖 표면'), findsNothing);
    expect(find.text('현재 프리셋: 내 팀 집중'), findsNothing);
    expect(find.text('알림 플레이북'), findsNothing);
    expect(find.text('리그 전체 알림'), findsNothing);
    expect(find.text('프리셋 적용'), findsNothing);
    expect(find.text('빠른 이동'), findsNothing);
    expect(find.text('경기 일정'), findsNothing);
    expect(find.text('순위표'), findsNothing);
    expect(find.text('기록실'), findsNothing);
    expect(find.text('뉴스'), findsNothing);
    expect(find.text('오늘과 이번 주'), findsNothing);
    expect(find.text('게임차와 흐름'), findsNothing);
    expect(find.text('선수와 팀 기록'), findsNothing);
    expect(find.text('짧은 경기 브리프'), findsNothing);
  });

  testWidgets('알림함은 내용 미리보기 없이 진입 버튼으로 보인다', (tester) async {
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
      find.text('알림함'),
      500,
      scrollable: mainScroll,
    );
    expect(find.text('푸시 알림 모아보기'), findsOneWidget);
    expect(find.text('최근 받은 알림을 확인합니다'), findsOneWidget);
    expect(find.text('득점, 홈런, 타석, 브리프가 수신 순서로 쌓입니다'), findsNothing);
    expect(find.text('라이브 액티비티'), findsNothing);
  });

  testWidgets('화면 모드는 시스템 라이트 다크 옵션을 제공하고 선택을 저장한다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        child: Consumer(
          builder: (context, ref, _) {
            final preference = ref.watch(appThemeModeProvider);
            return MaterialApp(
              theme: AppTheme.light,
              darkTheme: AppTheme.dark,
              themeMode: preference.themeMode,
              home: const SettingsScreen(),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('화면 모드'), findsOneWidget);
    expect(find.text('시스템'), findsOneWidget);
    expect(find.text('라이트'), findsOneWidget);
    expect(find.text('다크'), findsWidgets);

    await tester.tap(find.text('라이트'));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString(AppThemeModeNotifier.prefsKey),
      AppThemeModePreference.light.storageValue,
    );
    expect(find.text('라이트'), findsWidgets);
  });

  testWidgets('푸시 알림은 큰 모드와 세부 토글을 설정 첫 화면에서 제공한다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(theme: AppTheme.dark, home: const SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('푸시 알림'), findsOneWidget);
    expect(find.text('기본 대상'), findsOneWidget);
    expect(find.text('마이팀 선택 전'), findsOneWidget);
    expect(find.text('경기 전후 요약만 받기'), findsOneWidget);
    expect(find.text('경기 중 실시간 알림받기'), findsOneWidget);
    expect(find.text('안받기'), findsOneWidget);
    expect(find.text('경기 전후'), findsOneWidget);
    expect(find.text('경기 중 실시간'), findsOneWidget);
    expect(find.text('선발 라인업 공개'), findsOneWidget);
    expect(find.text('경기 시작과 시작 임박'), findsOneWidget);
    expect(find.text('경기 종료 결과'), findsOneWidget);
    expect(find.text('야구 브리프'), findsOneWidget);
    expect(find.text('득점'), findsOneWidget);
    expect(find.text('안타'), findsOneWidget);
    expect(find.text('홈런'), findsOneWidget);
    expect(find.text('역전'), findsOneWidget);
    expect(find.text('이닝 전환'), findsOneWidget);
    expect(find.text('타석 변화'), findsOneWidget);
  });

  testWidgets('안받기 선택은 저장된 moment와 delivery를 모두 끈다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(theme: AppTheme.dark, home: const SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('안받기'));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('push_notifications.game_start'), isFalse);
    expect(prefs.getBool('push_notifications.scoring'), isFalse);
    expect(prefs.getBool('push_notifications.hit'), isFalse);
    expect(prefs.getBool('push_notifications.baseball_info'), isFalse);
    expect(prefs.getString('push_notifications.game_start.delivery'), 'off');
    expect(prefs.getString('push_notifications.scoring.delivery'), 'off');
    expect(prefs.getString('push_notifications.hit.delivery'), 'off');
    expect(prefs.getString('push_notifications.baseball_info.delivery'), 'off');
    expect(find.text('푸시 알림이 꺼져 있습니다'), findsOneWidget);
  });

  testWidgets('설정 알림함 카드로 알림함에 진입한다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final router = GoRouter(
      initialLocation: '/settings',
      routes: [
        GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
        GoRoute(
          path: '/notifications',
          builder: (_, _) => const Text('notifications'),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    final mainScroll = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(
      find.text('푸시 알림 모아보기'),
      500,
      scrollable: mainScroll,
    );
    await tester.tap(find.text('푸시 알림 모아보기'));
    await tester.pumpAndSettle();

    expect(find.text('notifications'), findsOneWidget);
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

    expect(find.text('설정'), findsOneWidget);
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
