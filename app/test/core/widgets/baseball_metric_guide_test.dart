import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kbo_fans/core/theme/app_theme.dart';
import 'package:kbo_fans/core/widgets/baseball_metric_guide.dart';

void main() {
  testWidgets('선택 지표 설명과 OPS 상대지수 구분은 큰 글자에서도 유지된다', (tester) async {
    tester.view.physicalSize = const Size(320, 844);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2.4;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: const Scaffold(body: BaseballMetricGuideButton(metric: 'ERA')),
      ),
    );
    await tester.tap(find.text('기록 읽는 법'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('metric-guide-title')))
          .data,
      '평균자책 · ERA',
    );
    await tester.scrollUntilVisible(
      find.text('OPS 상대지수').first,
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('OPS 상대지수').first);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('리그 전체·구장 보정 지표가 아닙니다. 공식 OPS+나 wRC+와 구분해 주세요.'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.text('리그 전체·구장 보정 지표가 아닙니다. 공식 OPS+나 wRC+와 구분해 주세요.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
