import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kbo_fans/core/router/app_router.dart';
import 'package:kbo_fans/core/theme/app_theme.dart';

void main() {
  test('onboarding 상태 변경은 GoRouter 인스턴스를 재생성하지 않는다', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final router = container.read(routerProvider);

    container.read(onboardingDoneProvider.notifier).setValue(true);

    expect(identical(container.read(routerProvider), router), isTrue);
  });

  testWidgets('root push 화면은 iOS 스와이프 백 가능한 Cupertino route를 사용한다', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(onboardingDoneProvider.notifier).setValue(true);
    final router = container.read(routerProvider);
    router.go('/patch-notes');

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
      ),
    );
    await tester.pump();

    final rootNavigator = tester.widget<Navigator>(
      find.byType(Navigator).first,
    );
    expect(rootNavigator.pages.last, isA<CupertinoPage<void>>());
  });
}
