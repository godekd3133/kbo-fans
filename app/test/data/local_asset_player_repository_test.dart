import 'package:flutter_test/flutter_test.dart';
import 'package:kbo_fans/data/repositories/local_asset_player_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'missing local player snapshot does not fall back to mock players',
    () async {
      final repository = LocalAssetPlayerRepository();

      final players = await repository.getTeamPlayers('NO_TEAM', season: 2026);
      final stats = await repository.getTeamStats('NO_TEAM', season: 2026);

      expect(players, isEmpty);
      expect(stats.teamId, 'NO_TEAM');
      expect(stats.season, 2026);
      expect(stats.hitting, isEmpty);
      expect(stats.pitching, isEmpty);
    },
  );

  test(
    'missing local player detail fails instead of returning mock data',
    () async {
      final repository = LocalAssetPlayerRepository();

      expect(
        repository.getPlayerDetail('NO_PLAYER', season: 2026),
        throwsA(isA<StateError>()),
      );
    },
  );
}
