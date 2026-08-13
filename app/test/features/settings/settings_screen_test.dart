import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kbo_fans/core/theme/app_theme.dart';
import 'package:kbo_fans/core/theme/theme_mode_controller.dart';
import 'package:kbo_fans/data/providers.dart';
import 'package:kbo_fans/features/settings/settings_screen.dart';
import 'package:kbo_fans/services/push_notification_service.dart';
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

  testWidgets('320px 240% 화면 모드 선택지는 이름을 잘라내지 않는다', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.binding.setSurfaceSize(const Size(320, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.dark,
            home: MediaQuery(
              data: const MediaQueryData(
                size: Size(320, 844),
                textScaler: TextScaler.linear(2.4),
              ),
              child: const SettingsScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      for (final mode in ['시스템', '라이트', '다크']) {
        final control = find.bySemanticsLabel('$mode 모드');
        final label = find.descendant(of: control, matching: find.text(mode));
        final paragraph = tester.renderObject<RenderParagraph>(label);
        expect(
          paragraph.didExceedMaxLines,
          isFalse,
          reason: '$mode 모드 이름은 240% 크기에서도 전체가 보여야 한다',
        );
      }
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('푸시 알림은 프리셋 없이 항목별 토글을 설정 첫 화면에서 제공한다', (tester) async {
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
    expect(find.text('10개 선택됨'), findsOneWidget);
    expect(
      find.text('마이팀 알림은 팀을 선택해야 시작됩니다. 직접 팔로우한 경기 알림은 별도로 동작합니다.'),
      findsOneWidget,
    );
    expect(
      find.text(
        '여기서는 받을 알림을 선택합니다. 실제 수신은 알림 권한, 기기 등록, 서버 상태에 따라 달라질 수 있습니다.',
      ),
      findsOneWidget,
    );
    expect(find.text('10개 켜짐'), findsNothing);
    expect(find.text('경기 전후 요약만 받기'), findsNothing);
    expect(find.text('경기 중 실시간 알림받기'), findsNothing);
    expect(find.text('안받기'), findsNothing);
    expect(find.text('요약 디테일'), findsNothing);
    expect(find.text('실시간 디테일'), findsNothing);
    expect(find.text('경기 전후'), findsOneWidget);
    expect(find.text('경기 중'), findsOneWidget);
    expect(find.text('점수 변화 즉시'), findsOneWidget);
    expect(find.text('주자 상황 포함'), findsOneWidget);
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

  testWidgets('활성 설정의 보조 정보는 disabled가 아닌 supporting 색을 쓴다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          myTeamProvider.overrideWith(() => _FixedMyTeamNotifier('LG')),
        ],
        child: MaterialApp(theme: AppTheme.dark, home: const SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    for (final label in ['마이팀', '기본 대상', '라인업이 뜨면 알림']) {
      expect(
        tester.widget<Text>(find.text(label)).style?.color,
        AppTheme.darkColors.textSupporting,
        reason: '$label is readable supporting information, not disabled state',
      );
    }

    final mainScroll = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(
      find.text('최근 받은 알림을 확인합니다'),
      500,
      scrollable: mainScroll,
    );
    expect(
      tester.widget<Text>(find.text('최근 받은 알림을 확인합니다')).style?.color,
      AppTheme.darkColors.textSupporting,
    );

    await tester.scrollUntilVisible(
      find.text('0.1.0+1'),
      500,
      scrollable: mainScroll,
    );
    expect(
      tester.widget<Text>(find.text('0.1.0+1')).style?.color,
      AppTheme.darkColors.textSupporting,
    );
  });

  testWidgets('푸시 설정 로드 실패는 오류와 다시 시도를 보여주고 복구한다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var loadAttempts = 0;

    Future<PushNotificationSettings> loadSettings() async {
      loadAttempts += 1;
      if (loadAttempts == 1) {
        throw StateError('settings unavailable');
      }
      return const PushNotificationSettings.defaults();
    }

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          myTeamProvider.overrideWith(() => _FixedMyTeamNotifier('LG')),
        ],
        child: MaterialApp(
          theme: AppTheme.dark,
          home: SettingsScreen(pushSettingsLoader: loadSettings),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('알림 설정을 불러오지 못했습니다'), findsOneWidget);
    expect(find.text('연결을 확인한 뒤 다시 시도해 주세요.'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('push_notification_load_retry')),
    );
    await tester.pumpAndSettle();

    expect(loadAttempts, 2);
    expect(find.text('알림 설정을 불러오지 못했습니다'), findsNothing);
    expect(find.text('선발 라인업 공개'), findsOneWidget);
  });

  testWidgets('푸시 설정 다시 시도는 44px 터치 높이와 버튼 의미를 제공한다', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.binding.setSurfaceSize(const Size(390, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.dark,
            home: SettingsScreen(
              pushSettingsLoader: () async =>
                  throw StateError('settings unavailable'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final retryFinder = find.byKey(
        const ValueKey('push_notification_load_retry'),
      );
      final semanticsData = tester.getSemantics(retryFinder).getSemanticsData();

      expect(tester.getSize(retryFinder).height, greaterThanOrEqualTo(44));
      expect(semanticsData.flagsCollection.isButton, isTrue);
      expect(semanticsData.flagsCollection.isEnabled.toBoolOrNull(), isTrue);
      expect(semanticsData.hasAction(SemanticsAction.tap), isTrue);
      expect(semanticsData.label, contains('다시 시도'));
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('푸시 토글은 항목과 설명 그리고 켜짐 상태를 하나의 제어로 전달한다', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.binding.setSurfaceSize(const Size(390, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.dark,
            home: const SettingsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final hitToggle = find.byKey(const ValueKey('push_toggle_hit'));
      final node = tester.getSemantics(hitToggle);
      final data = node.getSemanticsData();

      expect(data.label, contains('안타'));
      expect(data.label, contains('주자 상황 포함'));
      expect(data.flagsCollection.isToggled.toBoolOrNull(), isTrue);
      expect(data.flagsCollection.isEnabled.toBoolOrNull(), isTrue);
      expect(data.hasAction(SemanticsAction.tap), isTrue);

      final duplicateControlNodes = <SemanticsNode>[];
      bool collectDuplicateControls(SemanticsNode child) {
        final childData = child.getSemanticsData();
        if (childData.hasAction(SemanticsAction.tap) ||
            childData.flagsCollection.isToggled.toBoolOrNull() != null) {
          duplicateControlNodes.add(child);
        }
        child.visitChildren(collectDuplicateControls);
        return true;
      }

      node.visitChildren(collectDuplicateControls);
      expect(
        duplicateControlNodes,
        isEmpty,
        reason: '토글 행 아래에 중복 탭/토글 semantics가 노출되면 안 된다',
      );
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('설정은 자동 프롬프트 없이 사용자가 탭할 때만 알림 권한을 요청한다', (tester) async {
    var requestCount = 0;
    String? requestedTeam;
    await tester.binding.setSurfaceSize(const Size(390, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          myTeamProvider.overrideWith(() => _FixedMyTeamNotifier('LG')),
        ],
        child: MaterialApp(
          theme: AppTheme.dark,
          home: SettingsScreen(
            pushPermissionStateLoader: () async => false,
            pushPermissionRequester: (myTeam) async {
              requestCount += 1;
              requestedTeam = myTeam;
              return true;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(requestCount, 0);
    expect(find.text('알림 권한을 확인해 주세요'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('push_permission_request')));
    await tester.pumpAndSettle();

    expect(requestCount, 1);
    expect(requestedTeam, 'LG');
    expect(find.text('알림 권한 허용됨'), findsOneWidget);
    expect(find.text('권한 다시 확인'), findsOneWidget);
  });

  testWidgets('알림 권한 확인이 실패해도 오류를 안내하고 다시 시도할 수 있다', (tester) async {
    var requestCount = 0;
    await tester.binding.setSurfaceSize(const Size(390, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.dark,
          home: SettingsScreen(
            pushPermissionStateLoader: () async => false,
            pushPermissionRequester: (_) async {
              requestCount += 1;
              if (requestCount == 1) {
                throw StateError('permission bridge unavailable');
              }
              return true;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final requestButton = find.byKey(const ValueKey('push_permission_request'));
    await tester.tap(requestButton);
    await tester.pumpAndSettle();

    expect(find.text('알림 권한을 확인하지 못했습니다'), findsOneWidget);
    expect(tester.widget<OutlinedButton>(requestButton).onPressed, isNotNull);

    await tester.tap(requestButton);
    await tester.pumpAndSettle();

    expect(requestCount, 2);
    expect(find.text('알림 권한 허용됨'), findsOneWidget);
    expect(find.text('알림 권한을 확인하지 못했습니다'), findsNothing);
  });

  testWidgets('320px 240% 푸시 토글은 항목과 설명을 잘라내지 않는다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.dark,
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 844),
              textScaler: TextScaler.linear(2.4),
            ),
            child: const SettingsScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final scrollable = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(
      find.text('경기 시작과 시작 임박'),
      500,
      scrollable: scrollable,
    );

    for (final copy in ['경기 시작과 시작 임박', '10분 전과 플레이볼']) {
      final paragraph = tester.renderObject<RenderParagraph>(find.text(copy));
      expect(
        paragraph.didExceedMaxLines,
        isFalse,
        reason: '$copy은 240% 크기에서도 전체가 보여야 한다',
      );
    }
  });

  testWidgets('푸시 알림은 항목별 토글 변경을 저장한다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(theme: AppTheme.dark, home: const SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('push_toggle_hit')));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('push_notifications.hit'), isFalse);
    expect(prefs.getString('push_notifications.hit.delivery'), 'off');

    await tester.tap(find.byKey(const ValueKey('push_toggle_hit')));
    await tester.pumpAndSettle();

    expect(prefs.getBool('push_notifications.hit'), isTrue);
    expect(prefs.getString('push_notifications.hit.delivery'), 'immediate');
  });

  testWidgets('모든 알림이 꺼진 상태에서도 개별 토글을 다시 켤 수 있다', (tester) async {
    SharedPreferences.setMockInitialValues({
      for (final key in [
        'game_start',
        'scoring',
        'hit',
        'homerun',
        'reversal',
        'game_end',
        'lineup_opened',
        'inning_change',
        'at_bat',
        'baseball_info',
      ]) ...{
        'push_notifications.$key': false,
        'push_notifications.$key.delivery': 'off',
      },
    });
    await tester.binding.setSurfaceSize(const Size(390, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          myTeamProvider.overrideWith(() => _FixedMyTeamNotifier('LG')),
        ],
        child: MaterialApp(theme: AppTheme.dark, home: const SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('선택 없음'), findsOneWidget);
    expect(find.text('받을 알림을 선택하지 않았습니다'), findsOneWidget);
    expect(find.text('득점'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('push_toggle_scoring')));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('push_notifications.scoring'), isTrue);
    expect(prefs.getString('push_notifications.scoring.delivery'), 'immediate');
    expect(find.text('1개 선택됨'), findsOneWidget);
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
    await tester.ensureVisible(find.text('푸시 알림 모아보기'));
    await tester.pumpAndSettle();
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

  testWidgets('320px 240% 세부 설정 항목은 자동으로 높이를 늘려 내용을 보여준다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.dark,
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 844),
              textScaler: TextScaler.linear(2.4),
            ),
            child: const SettingsScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('개인정보처리방침'),
      800,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    final paragraph = tester.renderObject<RenderParagraph>(
      find.text('개인정보처리방침'),
    );
    expect(
      paragraph.size.height,
      greaterThanOrEqualTo(
        paragraph.getMaxIntrinsicHeight(paragraph.size.width),
      ),
      reason: '항목 이름이 고정 높이 안에서 잘려서는 안 된다',
    );
  });
}

class _FixedMyTeamNotifier extends MyTeamNotifier {
  final String? value;

  _FixedMyTeamNotifier(this.value);

  @override
  String? build() => value;
}
