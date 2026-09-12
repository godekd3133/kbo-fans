import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kbo_fans/core/widgets/app_design_system.dart';

void main() {
  testWidgets('AppPageHeader keeps the back action separate from header copy', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppPageHeader(
              title: '푸시 알림 알림함',
              subtitle: '경기와 브리프에서 놓친 신호를 한 곳에서 확인합니다.',
              onBack: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final header = tester
          .getSemantics(find.byType(AppPageHeader))
          .getSemanticsData();
      expect(header.label, isEmpty);

      final back = tester
          .getSemantics(find.bySemanticsLabel('뒤로'))
          .getSemanticsData();
      expect(back.label, '뒤로');
      expect(back.flagsCollection.isButton, isTrue);
      expect(back.hasAction(SemanticsAction.tap), isTrue);
    } finally {
      semantics.dispose();
    }
  });
}
