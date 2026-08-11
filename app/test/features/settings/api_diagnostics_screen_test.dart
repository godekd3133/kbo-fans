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

    expect(find.textContaining('ready initialized=true'), findsOneWidget);
    expect(find.text('푸시 상태를 확인할 수 없습니다'), findsNothing);
  });
}

class _FakeApiClient extends ApiClient {
  _FakeApiClient() : super(enableRequestTiming: false);

  @override
  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    return switch (path) {
      '/health' => const {'status': 'ok'},
      '/scoreboard' => const {'games': <dynamic>[]},
      '/schedule' => const {'days': <dynamic>[]},
      _ => const <String, dynamic>{},
    };
  }
}
