import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
