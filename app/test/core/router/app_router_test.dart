import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kbo_fans/core/router/app_router.dart';
import 'package:kbo_fans/core/router/app_route_sanitizer.dart';
import 'package:kbo_fans/core/theme/app_theme.dart';
import 'package:kbo_fans/data/models/home_aggregate.dart';
import 'package:kbo_fans/data/models/schedule.dart';
import 'package:kbo_fans/data/providers.dart';

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
    router.go('/release-notes');

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

    final route = rootNavigator.pages.last.createRoute(
      tester.element(find.byType(Navigator).first),
    );
    expect(route, isA<PageRoute<void>>());
    expect(
      (route as PageRoute<void>).transitionDuration,
      const Duration(seconds: 1),
    );
  });

  testWidgets('부트 fade 전환은 기존 속도의 두 배 duration을 사용한다', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final router = container.read(routerProvider);
    router.go('/boot');

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
    final page = rootNavigator.pages.last as CustomTransitionPage<void>;
    expect(page.transitionDuration, const Duration(milliseconds: 360));
    expect(page.reverseTransitionDuration, const Duration(milliseconds: 280));
  });

  testWidgets('하단 탭 전환은 기존 속도의 두 배 duration을 사용한다', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(onboardingDoneProvider.notifier).setValue(true);
    final router = container.read(routerProvider);
    router.go('/settings');

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
      ),
    );
    await tester.pump();

    final navigators = tester
        .widgetList<Navigator>(find.byType(Navigator))
        .toList();
    final page = navigators.last.pages.last as CustomTransitionPage<void>;
    expect(page.transitionDuration, const Duration(milliseconds: 760));
    expect(page.reverseTransitionDuration, const Duration(milliseconds: 560));
  });

  testWidgets('뉴스에서 push한 shell 화면은 iOS 스와이프 백 가능한 Cupertino route를 사용한다', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        homeAggregateProvider.overrideWith(
          (ref, key) async => HomeAggregate(
            date: key.split('|').first,
            myTeam: null,
            myTeamBrief: null,
            kboBrief: null,
            quickItems: const [],
          ),
        ),
        standingsProvider.overrideWith((ref, season) async => <TeamStanding>[]),
      ],
    );
    addTearDown(container.dispose);

    container.read(onboardingDoneProvider.notifier).setValue(true);
    final router = container.read(routerProvider);
    router.go('/news');

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
      ),
    );
    await tester.pump();

    router.push('/standings', extra: AppRoutePresentation.swipeBack);
    await tester.pump();

    final navigators = tester
        .widgetList<Navigator>(find.byType(Navigator))
        .toList();
    expect(navigators.length, greaterThanOrEqualTo(2));
    expect(navigators.last.pages.last, isA<CupertinoPage<void>>());
  });
}
