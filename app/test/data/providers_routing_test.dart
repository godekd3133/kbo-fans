import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kbo_fans/core/config/app_config.dart';
import 'package:kbo_fans/data/providers.dart';
import 'package:kbo_fans/data/repositories/api_game_repository.dart';
import 'package:kbo_fans/data/repositories/api_player_repository.dart';
import 'package:kbo_fans/data/repositories/device_snapshot_player_repository.dart';
import 'package:kbo_fans/data/repositories/kbo_direct_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('repository routing defaults to no-backend direct data', () {
    AppConfig.initialize();
    final container = ProviderContainer();
    addTearDown(container.dispose);

    const useBackendApi = bool.fromEnvironment(
      'USE_BACKEND_API',
      defaultValue: false,
    );
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
  });
}
