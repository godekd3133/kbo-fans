import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kbo_fans/core/config/app_config.dart';
import 'package:kbo_fans/data/providers.dart';
import 'package:kbo_fans/data/repositories/kbo_direct_repository.dart';
import 'package:kbo_fans/data/repositories/local_asset_player_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('local native without API override uses local-native data paths', () {
    AppConfig.initialize();
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(AppConfig.instance.shouldPreferLocalNativeData, isTrue);
    expect(container.read(gameRepositoryProvider), isA<KboDirectRepository>());
    expect(
      container.read(playerRepositoryProvider),
      isA<LocalAssetPlayerRepository>(),
    );
  });
}
