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
}
