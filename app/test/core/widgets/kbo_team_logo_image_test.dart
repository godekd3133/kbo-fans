import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kbo_fans/core/theme/app_theme.dart';
import 'package:kbo_fans/core/widgets/kbo_team_logo_image.dart';

void main() {
  testWidgets('두산 로고는 다크 배경 대비판을 렌더링한다', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: KboTeamLogoImage(
            teamId: 'OB',
            fallback: '두산',
            size: 48,
            padding: 0,
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('kbo-team-logo-contrast-plate')),
      findsOneWidget,
    );
  });

  testWidgets('기본 대비가 충분한 팀 로고에는 대비판을 붙이지 않는다', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: KboTeamLogoImage(
            teamId: 'LG',
            fallback: 'LG',
            size: 48,
            padding: 0,
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('kbo-team-logo-contrast-plate')),
      findsNothing,
    );
  });

  testWidgets('두산 로고 대비판은 라이트모드에서도 밝은 받침을 사용한다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Center(
          child: KboTeamLogoImage(
            teamId: 'OB',
            fallback: '두산',
            size: 48,
            padding: 0,
          ),
        ),
      ),
    );

    final plate = tester.widget<Container>(
      find.byKey(const ValueKey('kbo-team-logo-contrast-plate')),
    );
    final decoration = plate.decoration as BoxDecoration;
    final fill = decoration.color;

    expect(fill, isNotNull);
    expect(fill!.computeLuminance(), greaterThan(0.92));
  });

  testWidgets('특정 표면에서는 다크 로고 대비판을 끌 수 있다', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: KboTeamLogoImage(
            teamId: 'OB',
            fallback: '두산',
            size: 48,
            padding: 0,
            useDarkLogoContrastPlate: false,
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('kbo-team-logo-contrast-plate')),
      findsNothing,
    );
  });
}
