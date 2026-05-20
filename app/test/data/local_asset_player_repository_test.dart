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
    'records overview uses verified exact current season snapshot',
    () async {
      final repository = LocalAssetPlayerRepository();

      final overview = await repository.getRecordsOverview(season: 2026);
      final leaderNames = [
        ...overview.avgLeaders.map((leader) => leader.name),
        ...overview.hrLeaders.map((leader) => leader.name),
        ...overview.opsLeaders.map((leader) => leader.name),
        ...overview.opsPlusLeaders.map((leader) => leader.name),
        ...overview.eraLeaders.map((leader) => leader.name),
      ];

      expect(overview.avgLeaders.first.name, '박성한');
      expect(overview.avgLeaders.first.value, '0.379');
      expect(overview.hrLeaders.first.name, '김도영');
      expect(overview.hrLeaders.first.value, '13');
      expect(overview.eraLeaders.first.name, '최민석');
      expect(overview.eraLeaders.first.value, '2.17');
      expect(leaderNames, isNot(contains('허경민')));
      expect(leaderNames, isNot(contains('함덕주')));
    },
  );

  test(
    'missing historical records overview does not borrow another season',
    () async {
      final repository = LocalAssetPlayerRepository();

      final overview = await repository.getRecordsOverview(season: 2025);

      expect(overview.season, 2025);
      expect(overview.avgLeaders, isEmpty);
      expect(overview.hrLeaders, isEmpty);
      expect(overview.opsLeaders, isEmpty);
      expect(overview.opsPlusLeaders, isEmpty);
      expect(overview.eraLeaders, isEmpty);
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
