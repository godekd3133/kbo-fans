import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kbo_fans/core/theme/app_theme.dart';
import 'package:kbo_fans/core/widgets/app_motion.dart';
import 'package:kbo_fans/core/widgets/main_scaffold.dart';

void main() {
  testWidgets('하단 탭은 비선택 상태도 읽을 수 있고 48px 터치 영역을 유지한다', (tester) async {
    final semantics = tester.ensureSemantics();
    _setViewport(tester, const Size(320, 568));

    final router = _testRouter();
    addTearDown(router.dispose);

    await tester.pumpWidget(
      MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
    );
    await tester.pumpAndSettle();

    final scheduleTextStyleFinder = find.byWidgetPredicate(
      (widget) =>
          widget is AnimatedDefaultTextStyle &&
          widget.child is Text &&
          (widget.child as Text).data == '일정',
    );
    expect(scheduleTextStyleFinder, findsOneWidget);
    final scheduleTextStyle = tester.widget<AnimatedDefaultTextStyle>(
      scheduleTextStyleFinder,
    );
    expect(scheduleTextStyle.style.color, AppTheme.darkColors.textSecondary);

    for (final label in ['홈', '일정', '기록', '브리핑', '설정']) {
      final pressable = find.ancestor(
        of: find.text(label),
        matching: find.byType(AppPressable),
      );
      expect(pressable, findsOneWidget);
      expect(tester.getSize(pressable).height, greaterThanOrEqualTo(48));
    }

    final selectedHome = find.ancestor(
      of: find.text('홈'),
      matching: find.byType(AppPressable),
    );
    expect(
      tester
          .getSemantics(selectedHome)
          .getSemanticsData()
          .flagsCollection
          .isSelected
          .toBoolOrNull(),
      isTrue,
    );
    semantics.dispose();
  });

  testWidgets('320px에서는 순위와 기록 하위 경로를 기록 탭으로 표시한다', (tester) async {
    final semantics = tester.ensureSemantics();
    _setViewport(tester, const Size(320, 568));

    final router = _testRouter(initialLocation: '/standings');
    addTearDown(router.dispose);

    await tester.pumpWidget(
      MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
    );
    await tester.pumpAndSettle();

    expect(find.byType(NavigationRail), findsNothing);
    expect(_selectedMobileDestination(tester, '기록'), isTrue);

    router.go('/records/team/LG');
    await tester.pumpAndSettle();

    expect(_selectedMobileDestination(tester, '기록'), isTrue);
    semantics.dispose();
  });

  testWidgets('700px에서는 순위를 직접 제공하는 rail을 쓰고 키보드 탐색을 지원한다', (tester) async {
    final semantics = tester.ensureSemantics();
    _setViewport(tester, const Size(700, 700));

    final router = _testRouter(initialLocation: '/standings');
    addTearDown(router.dispose);

    await tester.pumpWidget(
      MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
    );
    await tester.pumpAndSettle();

    final railFinder = find.byType(NavigationRail);
    expect(railFinder, findsOneWidget);
    expect(find.byType(AppPressable), findsNothing);
    expect(tester.widget<NavigationRail>(railFinder).selectedIndex, 2);
    expect(find.text('순위'), findsOneWidget);
    expect(
      find.ancestor(
        of: find.text('순위'),
        matching: find.byWidgetPredicate(
          (widget) => widget is Semantics && widget.properties.selected == true,
        ),
      ),
      findsOneWidget,
    );

    Focus.of(tester.element(find.text('일정'))).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(router.routeInformationProvider.value.uri.path, '/schedule');
    expect(tester.widget<NavigationRail>(railFinder).selectedIndex, 1);
    semantics.dispose();
  });

  testWidgets('1024px에서는 확장 rail을 사용한다', (tester) async {
    _setViewport(tester, const Size(1024, 768));

    final router = _testRouter();
    addTearDown(router.dispose);

    await tester.pumpWidget(
      MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
    );
    await tester.pumpAndSettle();

    final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
    expect(rail.extended, isTrue);
    expect(rail.destinations, hasLength(6));
    expect(find.text('순위'), findsOneWidget);
  });

  testWidgets('동작 줄이기 설정에서는 하단 탭 전환 애니메이션을 즉시 끝낸다', (tester) async {
    _setViewport(tester, const Size(320, 568));

    final router = GoRouter(
      initialLocation: '/home',
      routes: [
        ShellRoute(
          builder: (context, state, child) => MainScaffold(child: child),
          routes: [
            GoRoute(
              path: '/home',
              builder: (context, state) => const SizedBox.shrink(),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
      ),
    );
    await tester.pump();

    for (final label in ['홈', '일정', '기록', '브리핑', '설정']) {
      final animatedTextFinder = find.byWidgetPredicate(
        (widget) =>
            widget is AnimatedDefaultTextStyle &&
            widget.child is Text &&
            (widget.child as Text).data == label,
      );
      final animatedText = tester.widget<AnimatedDefaultTextStyle>(
        animatedTextFinder,
      );
      expect(animatedText.duration, Duration.zero);
    }
    for (final animatedScale in tester.widgetList<AnimatedScale>(
      find.byType(AnimatedScale),
    )) {
      expect(animatedScale.duration, Duration.zero);
    }
  });
}

GoRouter _testRouter({String initialLocation = '/home'}) {
  return GoRouter(
    initialLocation: initialLocation,
    routes: [
      ShellRoute(
        builder: (context, state, child) => MainScaffold(child: child),
        routes: [
          GoRoute(
            path: '/home',
            builder: (context, state) => const SizedBox.shrink(),
          ),
          GoRoute(
            path: '/schedule',
            builder: (context, state) => const SizedBox.shrink(),
          ),
          GoRoute(
            path: '/standings',
            builder: (context, state) => const SizedBox.shrink(),
          ),
          GoRoute(
            path: '/records',
            builder: (context, state) => const SizedBox.shrink(),
          ),
          GoRoute(
            path: '/records/team/:teamId',
            builder: (context, state) => const SizedBox.shrink(),
          ),
          GoRoute(
            path: '/news',
            builder: (context, state) => const SizedBox.shrink(),
          ),
          GoRoute(
            path: '/settings',
            builder: (context, state) => const SizedBox.shrink(),
          ),
        ],
      ),
    ],
  );
}

bool _selectedMobileDestination(WidgetTester tester, String label) {
  final destination = find.ancestor(
    of: find.text(label),
    matching: find.byType(AppPressable),
  );
  return tester
          .getSemantics(destination)
          .getSemanticsData()
          .flagsCollection
          .isSelected
          .toBoolOrNull() ??
      false;
}

void _setViewport(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}
