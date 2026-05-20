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

  test('current team records load exact bundled season snapshots', () async {
    final repository = LocalAssetPlayerRepository();

    final players = await repository.getTeamPlayers('LG', season: 2026);
    final stats = await repository.getTeamStats('LG', season: 2026);

    expect(players, isNotEmpty);
    expect(
      players.every((player) => player.imageUrl?.contains('/2026/') ?? false),
      isTrue,
    );
    expect(stats.season, 2026);
    expect(stats.hitting, isNotEmpty);
    expect(stats.pitching, isNotEmpty);
  });

  test('historical team players load exact bundled season snapshots', () async {
    final repository = LocalAssetPlayerRepository();

    final players = await repository.getTeamPlayers('LG', season: 2025);

    expect(players, isNotEmpty);
    expect(
      players.every((player) => player.imageUrl?.contains('/2025/') ?? false),
      isTrue,
    );
  });

  test(
    'incomplete historical team stats do not expose partial metrics',
    () async {
      final repository = LocalAssetPlayerRepository();

      final stats = await repository.getTeamStats('LG', season: 2025);

      expect(stats.season, 2025);
      expect(stats.hitting, isEmpty);
      expect(stats.pitching, isEmpty);
    },
  );

  test(
    'missing historical team snapshot does not borrow another season',
    () async {
      final repository = LocalAssetPlayerRepository();

      final players = await repository.getTeamPlayers('LG', season: 2021);
      final stats = await repository.getTeamStats('LG', season: 2021);

      expect(players, isEmpty);
      expect(stats.season, 2021);
      expect(stats.hitting, isEmpty);
      expect(stats.pitching, isEmpty);
    },
  );

  test(
    'historical bundled player snapshots include hitter and pitcher types',
    () async {
      final repository = LocalAssetPlayerRepository();

      final players = await repository.getTeamPlayers('LG', season: 2025);

      expect(
        players.where((player) => player.playerType.name == 'hitter'),
        isNotEmpty,
      );
      expect(
        players.where((player) => player.playerType.name == 'pitcher'),
        isNotEmpty,
      );
    },
  );
}
