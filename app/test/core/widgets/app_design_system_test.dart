import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kbo_fans/core/widgets/app_design_system.dart';
import 'package:kbo_fans/core/widgets/app_status_card.dart';

void main() {
  testWidgets('큰 글자의 상태 안내는 잘리지 않고 재시도와 다음 행동을 제공한다', (tester) async {
    tester.view.physicalSize = const Size(280, 568);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2.4;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    var retried = false;
    var continued = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AppStatusCard(
              title: '경기 정보를 불러오지 못했어요',
              description: '연결이 원활하지 않아요. 인터넷 연결을 확인하고 다시 시도해 주세요.',
              onAction: () => retried = true,
              secondaryLabel: '일정 보기',
              onSecondaryAction: () => continued = true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tester.widget<Text>(find.text('경기 정보를 불러오지 못했어요')).maxLines, isNull);
    await tester.ensureVisible(find.text('다시 시도'));
    await tester.tap(find.text('다시 시도'));
    await tester.ensureVisible(find.text('일정 보기'));
    await tester.tap(find.text('일정 보기'));
    expect(retried, isTrue);
    expect(continued, isTrue);
  });

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
