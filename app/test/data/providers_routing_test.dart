import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kbo_fans/core/config/app_config.dart';
import 'package:kbo_fans/data/providers.dart';
import 'package:kbo_fans/data/repositories/api_game_repository.dart';
import 'package:kbo_fans/data/repositories/device_snapshot_player_repository.dart';
import 'package:kbo_fans/data/repositories/kbo_direct_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('local native data path follows the direct scrape build flag', () {
    AppConfig.initialize();
    final container = ProviderContainer();
    addTearDown(container.dispose);

    const preferDirectScrape = bool.fromEnvironment(
      'PREFER_DIRECT_SCRAPE',
      defaultValue: false,
    );

    expect(AppConfig.instance.shouldPreferLocalNativeData, preferDirectScrape);
    expect(
      container.read(gameRepositoryProvider),
      preferDirectScrape
          ? isA<KboDirectRepository>()
          : isA<ApiGameRepository>(),
    );
    expect(
      container.read(playerRepositoryProvider),
      isA<DeviceSnapshotPlayerRepository>(),
    );
  });
}
