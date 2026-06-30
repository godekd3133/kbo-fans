import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kbo_fans/core/theme/app_theme.dart';
import 'package:kbo_fans/features/settings/release_notes_prompt.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'KBO Fans',
      packageName: 'com.kbofans.app',
      version: '0.1.8',
      buildNumber: '75',
      buildSignature: '',
    );
  });

  testWidgets('update prompt shows current release once and opens full notes', (
    tester,
  ) async {
    late BuildContext hostContext;
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, _) {
            hostContext = context;
            return const Scaffold(body: SizedBox.shrink());
          },
        ),
        GoRoute(
          path: '/release-notes',
          builder: (_, _) => const Scaffold(body: Text('전체 업데이트 소식 화면')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
    );
    await tester.pump();

    final promptFuture = showReleaseNotesPromptIfNeeded(hostContext);
    await tester.pumpAndSettle();

    expect(find.text('업데이트 소식'), findsOneWidget);
    expect(find.text('버전 0.1.8+75'), findsOneWidget);
    expect(find.textContaining('마이팀 경기 알림'), findsOneWidget);

    await tester.tap(find.widgetWithText(ElevatedButton, '전체 보기'));
    await tester.pumpAndSettle();
    await promptFuture;
    await tester.pumpAndSettle();

    expect(find.text('전체 업데이트 소식 화면'), findsOneWidget);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(releaseNotesSeenVersionPrefsKey), '0.1.8+75');

    await showReleaseNotesPromptIfNeeded(hostContext);
    await tester.pumpAndSettle();
    expect(find.text('버전 0.1.8+75'), findsNothing);
  });
}
