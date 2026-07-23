import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kbo_fans/core/widgets/app_motion.dart';

void main() {
  testWidgets('AppPressable은 버튼 의미와 키보드 활성화를 제공한다', (tester) async {
    final semantics = tester.ensureSemantics();
    var activationCount = 0;

    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppPressable(
              onTap: () => activationCount += 1,
              semanticLabel: '경기 상세 보기',
              semanticHint: '경기 상세 화면으로 이동',
              child: const Text('상세 보기'),
            ),
          ),
        ),
      );

      final semanticsData = tester
          .getSemantics(find.byType(AppPressable))
          .getSemanticsData();
      expect(semanticsData.flagsCollection.isButton, isTrue);
      expect(semanticsData.flagsCollection.isEnabled.toBoolOrNull(), isTrue);
      expect(semanticsData.hasAction(SemanticsAction.tap), isTrue);
      expect(semanticsData.label, '경기 상세 보기');
      expect(semanticsData.hint, '경기 상세 화면으로 이동');

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(FocusManager.instance.primaryFocus, isNotNull);
      final focusOutline = tester.widget<AnimatedContainer>(
        find.byKey(const ValueKey('app-pressable-focus-outline')),
      );
      final focusDecoration = focusOutline.decoration as BoxDecoration?;
      expect(focusDecoration?.border, isNotNull);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();

      expect(activationCount, 2);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('AppPressable은 활성 및 비활성 상태 모두 최소 히트 영역을 제공한다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppPressable(
                key: const ValueKey('enabled-pressable'),
                onTap: () {},
                child: const SizedBox(width: 18, height: 20),
              ),
              const AppPressable(
                key: ValueKey('disabled-pressable'),
                child: SizedBox(width: 18, height: 20),
              ),
            ],
          ),
        ),
      ),
    );

    for (final key in const ['enabled-pressable', 'disabled-pressable']) {
      final size = tester.getSize(find.byKey(ValueKey(key)));
      expect(size.width, greaterThanOrEqualTo(44));
      expect(size.height, greaterThanOrEqualTo(44));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('AppPressable은 더 엄격한 부모 제약 안에서 overflow하지 않는다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 32,
            height: 30,
            child: AppPressable(
              key: const ValueKey('tightly-constrained-pressable'),
              onTap: () {},
              child: const SizedBox(width: 18, height: 20),
            ),
          ),
        ),
      ),
    );

    expect(
      tester.getSize(
        find.byKey(const ValueKey('tightly-constrained-pressable')),
      ),
      const Size(32, 30),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('280px 폭의 작은 chip 행에서 overflow하지 않는다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 280,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: List.generate(
                5,
                (index) => AppPressable(
                  key: ValueKey('compact-chip-$index'),
                  onTap: index == 0 ? null : () {},
                  semanticSelected: index == 0,
                  child: SizedBox(
                    width: 32,
                    height: 24,
                    child: Center(child: Text('$index')),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    for (var index = 0; index < 5; index += 1) {
      final size = tester.getSize(find.byKey(ValueKey('compact-chip-$index')));
      expect(size, const Size(44, 44));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('선택된 비동작 항목과 실제 비활성 항목의 의미를 구분한다', (tester) async {
    final semantics = tester.ensureSemantics();

    try {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                AppPressable(
                  key: ValueKey('selected-pressable'),
                  semanticSelected: true,
                  semanticLabel: '현재 선택 필터',
                  semanticHint: '이미 선택됨',
                  child: Text('전체'),
                ),
                AppPressable(
                  key: ValueKey('disabled-pressable'),
                  semanticLabel: '사용할 수 없는 필터',
                  child: Text('포스트시즌'),
                ),
              ],
            ),
          ),
        ),
      );

      final selectedData = tester
          .getSemantics(find.byKey(const ValueKey('selected-pressable')))
          .getSemanticsData();
      final disabledData = tester
          .getSemantics(find.byKey(const ValueKey('disabled-pressable')))
          .getSemanticsData();

      expect(selectedData.flagsCollection.isSelected.toBoolOrNull(), isTrue);
      expect(selectedData.flagsCollection.isEnabled.toBoolOrNull(), isTrue);
      expect(selectedData.label, '현재 선택 필터');
      expect(selectedData.hint, '이미 선택됨');
      expect(selectedData.hasAction(SemanticsAction.tap), isFalse);

      expect(disabledData.flagsCollection.isSelected.toBoolOrNull(), isNull);
      expect(disabledData.flagsCollection.isEnabled.toBoolOrNull(), isFalse);
      expect(disabledData.label, '사용할 수 없는 필터');
      expect(disabledData.hasAction(SemanticsAction.tap), isFalse);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('AppPressable은 reduce motion에서도 즉시 활성화된다', (tester) async {
    var activationCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: AppPressable(
              onTap: () => activationCount += 1,
              child: const Text('즉시 열기'),
            ),
          ),
        ),
      ),
    );

    final focusOutline = tester.widget<AnimatedContainer>(
      find.byKey(const ValueKey('app-pressable-focus-outline')),
    );
    expect(focusOutline.duration, Duration.zero);
    expect(find.byType(AnimatedScale), findsNothing);

    await tester.tap(find.byType(AppPressable));
    await tester.pump();
    expect(activationCount, 1);
  });
}
