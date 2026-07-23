import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kbo_fans/core/config/app_config.dart';
import 'package:kbo_fans/core/config/api_endpoints.dart';
import 'package:kbo_fans/data/providers.dart';
import 'package:kbo_fans/data/repositories/api_game_repository.dart';
import 'package:kbo_fans/data/repositories/api_player_repository.dart';
import 'package:kbo_fans/data/repositories/device_snapshot_player_repository.dart';
import 'package:kbo_fans/data/repositories/kbo_direct_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('production API fallback uses the active Lightsail HTTPS endpoint', () {
    expect(productionApiBaseUrl, 'https://3-39-79-1.sslip.io/api');
  });

  test(
    'repository routing defaults to backend API data unless explicitly disabled',
    () {
      AppConfig.initialize();
      final container = ProviderContainer();
      addTearDown(container.dispose);

      const useBackendApiFlag = String.fromEnvironment(
        'USE_BACKEND_API',
        defaultValue: '',
      );
      final useBackendApi = useBackendApiFlag.isEmpty
          ? true
          : useBackendApiFlag == 'true';
      const apiBaseUrlOverride = String.fromEnvironment(
        'API_BASE_URL',
        defaultValue: '',
      );

      expect(AppConfig.instance.shouldUseBackendApi, useBackendApi);
      expect(AppConfig.instance.shouldUseDirectData, !useBackendApi);
      expect(
        AppConfig.instance.hasApiBaseUrlOverride,
        apiBaseUrlOverride.isNotEmpty,
      );
      if (apiBaseUrlOverride.isNotEmpty) {
        expect(AppConfig.instance.apiBaseUrl, apiBaseUrlOverride);
      }
      expect(
        container.read(gameRepositoryProvider),
        useBackendApi ? isA<ApiGameRepository>() : isA<KboDirectRepository>(),
      );
      expect(
        container.read(playerRepositoryProvider),
        useBackendApi
            ? isA<ApiPlayerRepository>()
            : isA<DeviceSnapshotPlayerRepository>(),
      );
    },
  );

  test('마이팀 저장은 느린 push registration convergence를 기다리지 않는다', () async {
    SharedPreferences.setMockInitialValues({});
    final convergenceStarted = Completer<void>();
    final allowConvergence = Completer<void>();
    final container = ProviderContainer(
      overrides: [
        myTeamRegistrationConvergenceProvider.overrideWithValue((
          myTeamId,
        ) async {
          expect(myTeamId, 'LG');
          convergenceStarted.complete();
          await allowConvergence.future;
        }),
      ],
    );
    addTearDown(container.dispose);

    await container.read(myTeamProvider.notifier).setTeam('LG');
    await convergenceStarted.future;

    final prefs = await SharedPreferences.getInstance();
    expect(container.read(myTeamProvider), 'LG');
    expect(prefs.getString('myTeam'), 'LG');
    expect(allowConvergence.isCompleted, isFalse);

    allowConvergence.complete();
  });

  test('background push registration 오류는 마이팀 저장에 전파되지 않는다', () async {
    SharedPreferences.setMockInitialValues({});
    final convergenceAttempted = Completer<void>();
    final container = ProviderContainer(
      overrides: [
        myTeamRegistrationConvergenceProvider.overrideWithValue((
          myTeamId,
        ) async {
          convergenceAttempted.complete();
          throw StateError('offline');
        }),
      ],
    );
    addTearDown(container.dispose);

    await expectLater(
      container.read(myTeamProvider.notifier).setTeam('KT'),
      completes,
    );
    await convergenceAttempted.future;
    await Future<void>.delayed(Duration.zero);

    final prefs = await SharedPreferences.getInstance();
    expect(container.read(myTeamProvider), 'KT');
    expect(prefs.getString('myTeam'), 'KT');
  });
}
