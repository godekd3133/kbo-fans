import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kbo_fans/core/theme/app_theme.dart';
import 'package:kbo_fans/core/widgets/app_artwork_card.dart';
import 'package:kbo_fans/data/providers.dart';
import 'package:kbo_fans/features/onboarding/onboarding_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
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
  });
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
