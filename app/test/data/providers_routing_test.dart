import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:kbo_fans/core/config/app_config.dart';
import 'package:kbo_fans/data/providers.dart';
import 'package:kbo_fans/data/repositories/api_game_repository.dart';
import 'package:kbo_fans/data/repositories/device_snapshot_player_repository.dart';
import 'package:kbo_fans/data/repositories/kbo_direct_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('direct scrape is allowed only for explicit local native builds', () {
    AppConfig.initialize();
    final container = ProviderContainer();
    addTearDown(container.dispose);

    const appEnv = String.fromEnvironment('APP_ENV', defaultValue: 'local');
    const apiBaseUrlOverride = String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: '',
    );
    const preferDirectScrape = bool.fromEnvironment(
      'PREFER_DIRECT_SCRAPE',
      defaultValue: false,
    );
    final shouldUseDirect =
        appEnv == 'local' &&
        !kIsWeb &&
        apiBaseUrlOverride.isEmpty &&
        preferDirectScrape;

    expect(AppConfig.instance.shouldPreferLocalNativeData, shouldUseDirect);
    expect(
      container.read(gameRepositoryProvider),
      shouldUseDirect ? isA<KboDirectRepository>() : isA<ApiGameRepository>(),
    );
    expect(
      container.read(playerRepositoryProvider),
      isA<DeviceSnapshotPlayerRepository>(),
    );
  });
}
