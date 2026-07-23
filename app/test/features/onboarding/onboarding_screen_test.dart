import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kbo_fans/core/theme/app_theme.dart';
import 'package:kbo_fans/core/widgets/app_artwork_card.dart';
import 'package:kbo_fans/core/widgets/app_motion.dart';
import 'package:kbo_fans/data/providers.dart';
import 'package:kbo_fans/features/onboarding/onboarding_screen.dart';
import 'package:kbo_fans/features/settings/release_notes_prompt.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('320x568 온보딩은 레이아웃 overflow 없이 표시된다', (tester) async {
    await _pumpOnboarding(
      tester,
      physicalSize: const Size(320, 568),
      textScaleFactor: 1,
    );

    expect(tester.takeException(), isNull);
    for (final label in [
      '경기 우선',
      '홈에서 먼저 보기',
      '득점 알림',
      '실시간 알림 받기',
      '순위 추적',
      '팀 순위 확인',
    ]) {
      final text = tester.widget<Text>(find.text(label));
      expect(text.style?.fontSize, greaterThanOrEqualTo(10));
      expect(
        find.ancestor(of: find.text(label), matching: find.byType(FittedBox)),
        findsNothing,
      );
    }
  });

  testWidgets('200% 글자 크기 온보딩은 레이아웃 overflow 없이 표시된다', (tester) async {
    await _pumpOnboarding(
      tester,
      physicalSize: const Size(390, 844),
      textScaleFactor: 2,
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('280px·240% 글자 크기에서 혜택 설명은 한 열로 온전히 흐른다', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await _pumpOnboarding(
        tester,
        physicalSize: const Size(280, 720),
        textScaleFactor: 2.4,
      );

      expect(tester.takeException(), isNull);
      final titleRects = [
        tester.getRect(find.text('경기 우선')),
        tester.getRect(find.text('득점 알림')),
        tester.getRect(find.text('순위 추적')),
      ];
      expect(titleRects[1].top, greaterThan(titleRects[0].bottom));
      expect(titleRects[2].top, greaterThan(titleRects[1].bottom));
      expect(find.text('홈에서 먼저 보기'), findsOneWidget);
      expect(find.text('실시간 알림 받기'), findsOneWidget);
      expect(find.text('팀 순위 확인'), findsOneWidget);

      final benefitSemantics = tester.getSemantics(find.text('경기 우선'));
      expect(benefitSemantics.label, contains('홈에서 먼저 보기'));
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('선택한 응원 팀은 스크린리더에 선택 상태를 노출한다', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await _pumpOnboarding(
        tester,
        physicalSize: const Size(390, 844),
        textScaleFactor: 1,
      );

      await tester.tap(find.text('LG'));
      await tester.pumpAndSettle();

      final semanticsData = tester
          .getSemantics(find.text('LG'))
          .getSemanticsData();
      expect(semanticsData.flagsCollection.isSelected.toBoolOrNull(), isTrue);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('나중에 선택은 44px 터치 높이와 활성 텍스트 색을 사용한다', (tester) async {
    await _pumpOnboarding(
      tester,
      physicalSize: const Size(390, 844),
      textScaleFactor: 1,
    );
    final labelFinder = find.text('나중에 선택');
    await tester.ensureVisible(labelFinder);
    await tester.pumpAndSettle();

    final pressableFinder = find.ancestor(
      of: labelFinder,
      matching: find.byType(AppPressable),
    );
    final label = tester.widget<Text>(labelFinder);

    expect(tester.getSize(pressableFinder).height, greaterThanOrEqualTo(44));
    expect(label.style?.color, AppColors.textSecondary);
  });

  testWidgets('온보딩은 독립 장식 이미지를 노출하지 않는다', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(theme: AppTheme.dark, home: OnboardingScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AppArtworkCard), findsNothing);
  });

  testWidgets('시작하기 저장 중에는 진행 상태를 보여주고 중복 탭을 막는다', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final saveStarted = Completer<void>();
    final allowSave = Completer<void>();
    final myTeamNotifier = _BlockingMyTeamNotifier(
      saveStarted: saveStarted,
      allowSave: allowSave,
    );

    final router = GoRouter(
      initialLocation: '/onboarding',
      routes: [
        GoRoute(
          path: '/onboarding',
          builder: (_, _) => const OnboardingScreen(),
        ),
        GoRoute(path: '/home', builder: (_, _) => const Text('home')),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [myTeamProvider.overrideWith(() => myTeamNotifier)],
        child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('LG').first);
    await tester.pump();
    await tester.ensureVisible(find.text('시작하기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('시작하기'));
    await tester.pump();
    await saveStarted.future;

    expect(find.text('시작 중입니다'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.tap(find.text('시작 중입니다'));
    await tester.pump();

    expect(myTeamNotifier.saveAttempts, 1);

    allowSave.complete();
    await tester.pumpAndSettle();

    expect(find.text('home'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(releaseNotesFreshInstallPendingPrefsKey), isTrue);
  });

  testWidgets('홈에서 연 edit 온보딩은 선택 완료 후 홈으로 돌아간다', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({'onboardingDone': true});

    final router = GoRouter(
      initialLocation: '/onboarding?mode=edit&redirect=/home',
      routes: [
        GoRoute(
          path: '/onboarding',
          builder: (_, state) => OnboardingScreen(
            isEditMode: state.uri.queryParameters['mode'] == 'edit',
            redirectTo: state.uri.queryParameters['redirect'] ?? '/home',
          ),
        ),
        GoRoute(path: '/home', builder: (_, _) => const Text('home')),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          myTeamProvider.overrideWith(
            () => _ImmediateMyTeamNotifier(initialTeamId: 'LG'),
          ),
        ],
        child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('선택 완료'));
    await tester.tap(find.text('선택 완료'));
    await tester.pumpAndSettle();

    expect(find.text('home'), findsOneWidget);
  });
}

Future<void> _pumpOnboarding(
  WidgetTester tester, {
  required Size physicalSize,
  required double textScaleFactor,
}) async {
  tester.view.physicalSize = physicalSize;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = textScaleFactor;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  SharedPreferences.setMockInitialValues({});

  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(theme: AppTheme.dark, home: const OnboardingScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

class _BlockingMyTeamNotifier extends MyTeamNotifier {
  final Completer<void> saveStarted;
  final Completer<void> allowSave;
  int saveAttempts = 0;

  _BlockingMyTeamNotifier({required this.saveStarted, required this.allowSave});

  @override
  Future<void> setTeam(String? teamId) async {
    saveAttempts += 1;
    state = teamId;
    if (!saveStarted.isCompleted) {
      saveStarted.complete();
    }
    await allowSave.future;
  }
}

class _ImmediateMyTeamNotifier extends MyTeamNotifier {
  final String? initialTeamId;

  _ImmediateMyTeamNotifier({required this.initialTeamId});

  @override
  String? build() => initialTeamId;

  @override
  Future<void> setTeam(String? teamId) async {
    state = teamId;
  }
}
