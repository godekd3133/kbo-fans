import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kbo_fans/core/config/app_config.dart';
import 'package:kbo_fans/core/router/app_router.dart';
import 'package:kbo_fans/core/widgets/dev_console.dart';
import 'package:kbo_fans/data/providers.dart';
import 'package:kbo_fans/features/records/records_screen.dart';
import 'package:kbo_fans/main.dart';
import 'package:kbo_fans/services/push_notification_service.dart';

void main() {
  setUpAll(() {
    AppConfig.initialize();
  });

  testWidgets('앱 루트가 렌더링된다', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({'onboardingDone': false});

    await tester.pumpWidget(const ProviderScope(child: KboFansApp()));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(DevConsoleOverlay), findsOneWidget);
  });

  testWidgets('앱 전역 자동 leading은 한국어 뒤로 이름을 제공한다', (tester) async {
    SharedPreferences.setMockInitialValues({'onboardingDone': true});
    final semantics = tester.ensureSemantics();
    final container = ProviderContainer(retry: _disableRetry);
    addTearDown(container.dispose);
    container.read(onboardingDoneProvider.notifier).setValue(true);
    final router = container.read(routerProvider)..go('/settings');

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const KboFansApp(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    router.push('/release-notes');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byTooltip('뒤로'), findsOneWidget);
    expect(find.bySemanticsLabel('뒤로'), findsOneWidget);
    semantics.dispose();
  });

  test('resume sync는 loading 중인 scoreboard를 다시 invalidate하지 않는다', () async {
    final pendingScoreboard = Completer<List<int>>();
    var invalidations = 0;

    final result = refreshOnResumeUnlessLoading(
      current: const AsyncLoading<List<int>>(),
      invalidate: () => invalidations += 1,
      readFuture: () => pendingScoreboard.future,
    );

    expect(invalidations, 0);

    pendingScoreboard.complete([1]);

    expect(await result, [1]);
  });

  test('resume sync는 완료된 scoreboard를 한 번 갱신한다', () async {
    var invalidations = 0;

    final result = await refreshOnResumeUnlessLoading(
      current: const AsyncData<List<int>>([0]),
      invalidate: () => invalidations += 1,
      readFuture: () async => [1],
    );

    expect(invalidations, 1);
    expect(result, [1]);
  });

  testWidgets('포그라운드 push는 인앱 팝업을 띄우고 안전한 route로 이동한다', (tester) async {
    SharedPreferences.setMockInitialValues({
      'onboardingDone': true,
      'myTeam': 'LG',
    });
    final container = ProviderContainer(retry: _disableRetry);
    addTearDown(container.dispose);
    container.read(onboardingDoneProvider.notifier).setValue(true);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const KboFansApp(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 1000));

    PushNotificationService.instance.emitForegroundNotificationForTesting(
      const PushForegroundNotification(
        title: '득점',
        body: 'LG 득점 · 스코어 2:1',
        route: '/notifications',
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('득점'), findsOneWidget);
    expect(find.text('LG 득점 · 스코어 2:1'), findsOneWidget);

    await tester.tap(find.text('보기'));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(
      container
          .read(routerProvider)
          .routerDelegate
          .currentConfiguration
          .uri
          .path,
      '/notifications',
    );
  });

  testWidgets('기록실 리그 요약 오류를 숨기지 않는다', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          recordsOverviewProvider.overrideWith((ref, season) {
            throw Exception('offline');
          }),
        ],
        child: const MaterialApp(home: RecordsScreen()),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('리그 기록을 불러올 수 없습니다'), findsOneWidget);
    expect(find.text('데이터를 불러오지 못했습니다. 잠시 후 다시 시도해주세요.'), findsOneWidget);
  });
}

Duration? _disableRetry(int retryCount, Object error) => null;
