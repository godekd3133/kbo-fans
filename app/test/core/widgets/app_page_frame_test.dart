import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kbo_fans/core/widgets/app_design_system.dart';
import 'package:kbo_fans/core/widgets/app_motion.dart';
import 'package:kbo_fans/core/widgets/app_page_frame.dart';

void main() {
  testWidgets('기본 최대폭은 320px에서 화면 폭을 사용한다', (tester) async {
    await _pumpFrame(tester, viewportWidth: 320);

    expect(tester.getSize(find.byKey(_contentKey)).width, 320);
  });

  testWidgets('기본 최대폭은 700px 태블릿에서 화면 폭까지 확장된다', (tester) async {
    await _pumpFrame(tester, viewportWidth: 700);

    expect(tester.getSize(find.byKey(_contentKey)).width, 700);
  });

  testWidgets('기본 최대폭은 1024px에서 720px로 제한된다', (tester) async {
    await _pumpFrame(tester, viewportWidth: 1024);

    expect(tester.getSize(find.byKey(_contentKey)).width, 720);
  });

  testWidgets('호출자가 명시한 maxWidth는 태블릿에서도 우선한다', (tester) async {
    await _pumpFrame(tester, viewportWidth: 1024, maxWidth: 500);

    expect(tester.getSize(find.byKey(_contentKey)).width, 500);
  });

  testWidgets('페이지 frame은 부모 요약과 자식 action semantics를 분리한다', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppPageFrame(
              child: Column(
                children: [
                  const Text('페이지 제목'),
                  AppPressable(
                    semanticLabel: '세부 보기',
                    onTap: () {},
                    child: const Text('열기'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final frame = tester
          .getSemantics(find.byType(AppPageFrame))
          .getSemanticsData();
      expect(frame.label, isEmpty);

      final scaffold = tester
          .getSemantics(find.byType(Scaffold))
          .getSemanticsData();
      expect(scaffold.label, isEmpty);

      final action = tester
          .getSemantics(find.bySemanticsLabel('세부 보기'))
          .getSemanticsData();
      expect(action.flagsCollection.isButton, isTrue);
      expect(action.hasAction(SemanticsAction.tap), isTrue);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('페이지 frame은 헤더와 확장 본문에서도 상위 요약을 만들지 않는다', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppPageFrame(
              child: Column(
                children: [
                  const AppPageHeader(
                    eyebrow: '기록실',
                    title: '선수 상세',
                    subtitle: '대표 기록을 확인합니다.',
                  ),
                  const Expanded(child: Text('본문 데이터')),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final frame = tester
          .getSemantics(find.byType(AppPageFrame))
          .getSemanticsData();
      expect(frame.label, isEmpty);
      final scaffold = tester
          .getSemantics(find.byType(Scaffold))
          .getSemanticsData();
      expect(scaffold.label, isEmpty);
    } finally {
      semantics.dispose();
    }
  });
}

const _contentKey = ValueKey('app-page-frame-test-content');

Future<void> _pumpFrame(
  WidgetTester tester, {
  required double viewportWidth,
  double? maxWidth,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(viewportWidth, 700);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: AppPageFrame(
          maxWidth: maxWidth,
          child: const SizedBox(
            key: _contentKey,
            width: double.infinity,
            height: 20,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}
