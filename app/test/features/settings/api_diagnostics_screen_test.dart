import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kbo_fans/core/config/app_config.dart';
import 'package:kbo_fans/core/theme/app_theme.dart';
import 'package:kbo_fans/data/api/api_client.dart';
import 'package:kbo_fans/data/providers.dart';
import 'package:kbo_fans/features/settings/api_diagnostics_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  AppConfig.initialize();

  testWidgets('푸시 진단 오류와 재시도 진행 상태를 숨기지 않는다', (tester) async {
    final initialResult = Completer<Map<String, dynamic>>();
    final retryResult = Completer<Map<String, dynamic>>();
    var pushAttempts = 0;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiClientProvider.overrideWithValue(_FakeApiClient())],
        child: MaterialApp(
          theme: AppTheme.dark,
          home: ApiDiagnosticsScreen(
            pushStateLoader: () {
              pushAttempts += 1;
              if (pushAttempts == 1) {
                return initialResult.future;
              }
              return retryResult.future;
            },
          ),
        ),
      ),
    );
    await tester.pump();
    initialResult.completeError(StateError('private push detail'));
    await tester.pumpAndSettle();

    expect(find.text('푸시 상태를 확인할 수 없습니다'), findsOneWidget);
    expect(find.text('푸시 상태 다시 시도'), findsOneWidget);
    expect(find.textContaining('private push detail'), findsNothing);
    final pushErrorCard = find.byKey(
      const ValueKey('api-diagnostics-push-error'),
    );
    expect(
      tester
          .widgetList<Text>(
            find.descendant(of: pushErrorCard, matching: find.byType(Text)),
          )
          .where((text) => text.style?.fontSize == 12)
          .every(
            (text) => text.style?.color != AppTheme.darkColors.textDisabled,
          ),
      isTrue,
    );

    await tester.ensureVisible(
      find.byKey(const ValueKey('api-diagnostics-push-retry')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('api-diagnostics-push-retry')));
    await tester.pump();

    expect(pushAttempts, 2);
    expect(find.text('푸시 상태 확인 중'), findsOneWidget);

    retryResult.complete(const {
      'status': 'ready',
      'initialized': true,
      'tokenReady': true,
      'remotePushAvailable': true,
      'localGameEventAlertsEnabled': true,
      'localGameEventAlertsForced': false,
      'topics': <String>['team_lg'],
      'apiBaseUrl': 'https://api.example.test',
    });
    await tester.pumpAndSettle();

    expect(find.textContaining('ready initialized=true'), findsNothing);
    final details = find.byKey(const ValueKey('api-diagnostics-details-push'));
    await tester.ensureVisible(details);
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: details, matching: find.text('상세 정보')),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('ready initialized=true'), findsOneWidget);
    expect(find.text('푸시 상태를 확인할 수 없습니다'), findsNothing);
  });

  testWidgets('초기화만 됐고 토큰이 없으면 알림 기기 등록을 확인된 것으로 표시하지 않는다', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [apiClientProvider.overrideWithValue(_FakeApiClient())],
          child: MaterialApp(
            theme: AppTheme.dark,
            home: ApiDiagnosticsScreen(
              pushStateLoader: () async => {
                ..._readyPushState,
                'tokenReady': false,
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .getSemantics(
              find.byKey(const ValueKey('api-diagnostics-semantics-push')),
            )
            .label,
        '기기 알림 상태, 확인 실패',
      );
      expect(find.textContaining('initialized=true'), findsNothing);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('토큰이 있어도 초기화 실패 상태를 확인된 기기 정보로 표시하지 않는다', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [apiClientProvider.overrideWithValue(_FakeApiClient())],
          child: MaterialApp(
            theme: AppTheme.dark,
            home: ApiDiagnosticsScreen(
              pushStateLoader: () async => {
                ..._readyPushState,
                'status': 'failed',
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .getSemantics(
              find.byKey(const ValueKey('api-diagnostics-semantics-push')),
            )
            .label,
        '기기 알림 상태, 확인 실패',
      );
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('진단 중 빠른 다시 진단 탭은 중복 요청을 만들지 않는다', (tester) async {
    final initialPush = Completer<Map<String, dynamic>>();
    final refreshedPush = Completer<Map<String, dynamic>>();
    var pushAttempts = 0;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiClientProvider.overrideWithValue(_FakeApiClient())],
        child: MaterialApp(
          theme: AppTheme.dark,
          home: ApiDiagnosticsScreen(
            pushStateLoader: () {
              pushAttempts += 1;
              return pushAttempts == 1
                  ? initialPush.future
                  : refreshedPush.future;
            },
          ),
        ),
      ),
    );
    await tester.pump();

    final refreshButton = find.byType(IconButton).first;
    expect(pushAttempts, 1);
    expect(tester.widget<IconButton>(refreshButton).onPressed, isNotNull);

    await tester.tap(refreshButton);
    await tester.pump();

    expect(pushAttempts, 2);
    expect(tester.widget<IconButton>(refreshButton).onPressed, isNull);
    expect(find.byType(CircularProgressIndicator), findsAtLeastNWidgets(1));

    refreshedPush.complete(_readyPushState);
    initialPush.complete(_readyPushState);
    await tester.pumpAndSettle();

    expect(tester.widget<IconButton>(refreshButton).onPressed, isNotNull);
  });

  testWidgets('진단 카드는 상태와 detail을 하나의 접근성 요약으로 읽는다', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [apiClientProvider.overrideWithValue(_FakeApiClient())],
          child: MaterialApp(
            theme: AppTheme.dark,
            home: ApiDiagnosticsScreen(
              pushStateLoader: () async => _readyPushState,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final data = tester
          .getSemantics(
            find.byKey(const ValueKey('api-diagnostics-semantics-health')),
          )
          .getSemanticsData();
      expect(data.label, '서버 응답, 응답 확인');
      expect(find.text('status=ok'), findsNothing);
      final details = find.byKey(
        const ValueKey('api-diagnostics-details-health'),
      );
      final toggle = find.descendant(of: details, matching: find.text('상세 정보'));
      expect(
        tester.getSemantics(toggle).getSemanticsData().flagsCollection.isButton,
        isTrue,
      );
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(find.text('status=ok'), findsOneWidget);
    } finally {
      semantics.dispose();
    }
  });
}

const _readyPushState = <String, dynamic>{
  'status': 'ready',
  'initialized': true,
  'tokenReady': true,
  'remotePushAvailable': true,
  'localGameEventAlertsEnabled': true,
  'localGameEventAlertsForced': false,
  'topics': <String>['team_lg'],
  'apiBaseUrl': 'https://api.example.test',
};

class _FakeApiClient extends ApiClient {
  _FakeApiClient() : super(enableRequestTiming: false);

  @override
  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    return switch (path) {
      '/health' => const {'status': 'ok'},
      '/scoreboard/home' => const {'games': <dynamic>[]},
      '/schedule' => const {'days': <dynamic>[]},
      _ => const <String, dynamic>{},
    };
  }
}
