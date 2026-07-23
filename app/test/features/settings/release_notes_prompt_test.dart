import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kbo_fans/core/theme/app_theme.dart';
import 'package:kbo_fans/features/settings/release_notes.dart';
import 'package:kbo_fans/features/settings/release_notes_prompt.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'KBO Fans',
      packageName: 'com.kbofans.app',
      version: '0.1.20',
      buildNumber: '88',
      buildSignature: '',
    );
  });

  test('current patch note is available for the installed version', () async {
    final currentVersion = await loadCurrentAppVersion(fallbackVersion: '');
    final data = await loadReleaseNotes();

    expect(currentVersion, '0.1.20+88');
    expect(data.releases.first.version, '0.1.20+88');
    expect(findInstalledReleaseNote(data.releases, currentVersion), isNotNull);
  });

  testWidgets(
    'fresh install stores the current version without showing a prompt',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        releaseNotesFreshInstallPendingPrefsKey: true,
      });
      late BuildContext promptContext;
      const currentVersion = '0.1.19+87';
      const release = ReleaseNote(
        version: currentVersion,
        subtitle: '새로고침 안정성',
        notes: ['고쳤어요: 오늘 경기 정보를 안정적으로 보여줍니다.'],
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Builder(
            builder: (context) {
              promptContext = context;
              return const Scaffold(body: SizedBox.shrink());
            },
          ),
        ),
      );
      await tester.pump();

      final promptFuture = showReleaseNotesPromptIfNeeded(
        promptContext,
        currentVersionLoader: () async => currentVersion,
        releaseNotesLoader: () async => const ReleaseNotesData(
          currentVersion: currentVersion,
          releases: [release],
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final promptWasShown = find.text('업데이트 소식').evaluate().isNotEmpty;
      if (promptWasShown) {
        await tester.tap(find.widgetWithText(OutlinedButton, '닫기'));
        await tester.pump();
      }
      await promptFuture;

      expect(promptWasShown, isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(releaseNotesSeenVersionPrefsKey), currentVersion);
      expect(
        prefs.containsKey(releaseNotesFreshInstallPendingPrefsKey),
        isFalse,
      );
    },
  );

  testWidgets(
    'existing install without a legacy seen key still sees the update prompt',
    (tester) async {
      late BuildContext promptContext;
      const currentVersion = '0.1.19+87';
      const release = ReleaseNote(
        version: currentVersion,
        subtitle: '새로고침 안정성',
        notes: ['고쳤어요: 오늘 경기 정보를 안정적으로 보여줍니다.'],
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Builder(
            builder: (context) {
              promptContext = context;
              return const Scaffold(body: SizedBox.shrink());
            },
          ),
        ),
      );
      await tester.pump();

      final promptFuture = showReleaseNotesPromptIfNeeded(
        promptContext,
        currentVersionLoader: () async => currentVersion,
        releaseNotesLoader: () async => const ReleaseNotesData(
          currentVersion: currentVersion,
          releases: [release],
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('업데이트 소식'), findsOneWidget);
      await tester.tap(find.widgetWithText(OutlinedButton, '닫기'));
      await tester.pump();
      await promptFuture;
    },
  );

  testWidgets('update prompt shows the current release once', (tester) async {
    SharedPreferences.setMockInitialValues({
      releaseNotesSeenVersionPrefsKey: '0.1.18+86',
    });
    late BuildContext promptContext;
    const currentVersion = '0.1.19+87';
    const release = ReleaseNote(
      version: currentVersion,
      subtitle: '새로고침 안정성',
      notes: ['고쳤어요: 해외에 있거나 자정 무렵에도 오늘 경기 정보를 안정적으로 보여줍니다.'],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Builder(
          builder: (context) {
            promptContext = context;
            return const Scaffold(body: SizedBox.shrink());
          },
        ),
      ),
    );
    await tester.pump();
    expect(promptContext.mounted, isTrue);

    final promptFuture = showReleaseNotesPromptIfNeeded(
      promptContext,
      currentVersionLoader: () async => currentVersion,
      releaseNotesLoader: () async => const ReleaseNotesData(
        currentVersion: currentVersion,
        releases: [release],
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('업데이트 소식'), findsOneWidget);
    expect(find.text('버전 $currentVersion'), findsOneWidget);
    expect(find.textContaining('해외에 있거나 자정 무렵'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, '닫기'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await promptFuture;

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(releaseNotesSeenVersionPrefsKey), currentVersion);

    await showReleaseNotesPromptIfNeeded(
      promptContext,
      currentVersionLoader: () async => currentVersion,
      releaseNotesLoader: () async => const ReleaseNotesData(
        currentVersion: currentVersion,
        releases: [release],
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('버전 $currentVersion'), findsNothing);
  });
}
