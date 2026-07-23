import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kbo_fans/core/theme/app_theme.dart';
import 'package:kbo_fans/core/widgets/app_motion.dart';
import 'package:kbo_fans/core/widgets/main_scaffold.dart';

void main() {
  testWidgets('하단 탭은 비선택 상태도 읽을 수 있고 48px 터치 영역을 유지한다', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));

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
            GoRoute(
              path: '/schedule',
              builder: (context, state) => const SizedBox.shrink(),
            ),
            GoRoute(
              path: '/records',
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

  testWidgets('동작 줄이기 설정에서는 하단 탭 전환 애니메이션을 즉시 끝낸다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));

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
