import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kbo_fans/core/widgets/app_metadata_text.dart';

void main() {
  test('metadata preserves baseball names and decimal values', () {
    expect(metadataItems('출루·장타 0.301'), ['출루·장타 0.301']);
    expect(metadataItems('잠실 • 18:30 · 7회말'), ['잠실', '18:30', '7회말']);
  });
  testWidgets(
    'metadata uses separate wrapping fields with no visible bullets',
    (tester) async {
      tester.view.physicalSize = const Size(280, 568);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2.4;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: Padding(
                padding: EdgeInsets.all(16),
                child: AppMetadataText(
                  '잠실 • 18:30 · 7회말',
                  style: TextStyle(fontSize: 14),
                ),
              ),
            ),
          ),
        );
        expect(find.text('잠실'), findsOneWidget);
        expect(find.text('18:30'), findsOneWidget);
        expect(find.text('7회말'), findsOneWidget);
        expect(find.textContaining('•'), findsNothing);
        expect(find.textContaining(' · '), findsNothing);
        expect(
          tester.getSemantics(find.byType(AppMetadataText)).label,
          '잠실, 18:30, 7회말',
        );
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    },
  );
}
