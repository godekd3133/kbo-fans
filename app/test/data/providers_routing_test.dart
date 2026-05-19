import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kbo_fans/core/config/app_config.dart';
import 'package:kbo_fans/data/providers.dart';
import 'package:kbo_fans/data/repositories/api_game_repository.dart';
import 'package:kbo_fans/data/repositories/device_snapshot_player_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('local native without API override keeps API-backed data paths', () {
    AppConfig.initialize();
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(AppConfig.instance.shouldPreferLocalNativeData, isFalse);
    expect(container.read(gameRepositoryProvider), isA<ApiGameRepository>());
    expect(
      container.read(playerRepositoryProvider),
      isA<DeviceSnapshotPlayerRepository>(),
    );
  });
}
