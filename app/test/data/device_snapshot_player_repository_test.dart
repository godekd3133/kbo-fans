import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kbo_fans/data/models/player.dart';
import 'package:kbo_fans/data/models/records_overview.dart';
import 'package:kbo_fans/data/models/team_records_bundle.dart';
import 'package:kbo_fans/data/models/team_stats.dart';
import 'package:kbo_fans/data/repositories/device_snapshot_player_repository.dart';
import 'package:kbo_fans/data/repositories/player_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'current season legacy device snapshot without savedAt is ignored',
    () async {
      SharedPreferences.setMockInitialValues({
        _snapshotKey('teamStats:KT:2026'): jsonEncode({
          'teamId': 'KT',
          'season': 2026,
          'hitting': {'AVG': '0.382'},
          'pitching': {'ERA': '6.00'},
        }),
      });
      final repository = DeviceSnapshotPlayerRepository(
        primary: _ThrowingPlayerRepository(),
        fallback: _FallbackPlayerRepository(
          teamStats: _emptyStats(teamId: 'KT', season: 2026),
        ),
        now: () => DateTime.utc(2026, 5, 20, 12),
      );

      final stats = await repository.getTeamStats('KT', season: 2026);

      expect(stats.hitting, isEmpty);
      expect(stats.pitching, isEmpty);
    },
  );

  test(
    'fresh current season device snapshot is reused after API failure',
    () async {
      SharedPreferences.setMockInitialValues({
        _snapshotKey('teamStats:KT:2026'): jsonEncode({
          'savedAt': DateTime.utc(2026, 5, 20, 11, 50).toIso8601String(),
          'payload': {
            'teamId': 'KT',
            'season': 2026,
            'hitting': {'AVG': '0.287', 'G': '43'},
            'pitching': {'ERA': '4.50', 'G': '43'},
          },
        }),
      });
      final repository = DeviceSnapshotPlayerRepository(
        primary: _ThrowingPlayerRepository(),
        fallback: _FallbackPlayerRepository(
          teamStats: _emptyStats(teamId: 'KT', season: 2026),
        ),
        now: () => DateTime.utc(2026, 5, 20, 12),
      );

      final stats = await repository.getTeamStats('KT', season: 2026);

      expect(stats.hitting['AVG'], '0.287');
      expect(stats.hitting['G'], '43');
      expect(stats.pitching['ERA'], '4.50');
    },
  );

  test('stale current season device snapshot is ignored', () async {
    SharedPreferences.setMockInitialValues({
      _snapshotKey('teamStats:KT:2026'): jsonEncode({
        'savedAt': DateTime.utc(2026, 5, 20, 5).toIso8601String(),
        'payload': {
          'teamId': 'KT',
          'season': 2026,
          'hitting': {'AVG': '0.382'},
          'pitching': {'ERA': '6.00'},
        },
      }),
    });
    final repository = DeviceSnapshotPlayerRepository(
      primary: _ThrowingPlayerRepository(),
      fallback: _FallbackPlayerRepository(
        teamStats: _emptyStats(teamId: 'KT', season: 2026),
      ),
      now: () => DateTime.utc(2026, 5, 20, 12),
    );

    final stats = await repository.getTeamStats('KT', season: 2026);

    expect(stats.hitting, isEmpty);
    expect(stats.pitching, isEmpty);
  });

  test('historical legacy device snapshot remains usable', () async {
    SharedPreferences.setMockInitialValues({
      _snapshotKey('teamStats:KT:2025'): jsonEncode({
        'teamId': 'KT',
        'season': 2025,
        'hitting': {'AVG': '0.277'},
        'pitching': {'ERA': '4.11'},
      }),
    });
    final repository = DeviceSnapshotPlayerRepository(
      primary: _ThrowingPlayerRepository(),
      fallback: _FallbackPlayerRepository(
        teamStats: _emptyStats(teamId: 'KT', season: 2025),
      ),
      now: () => DateTime.utc(2026, 5, 20, 12),
    );

    final stats = await repository.getTeamStats('KT', season: 2025);

    expect(stats.hitting['AVG'], '0.277');
    expect(stats.pitching['ERA'], '4.11');
  });

  test('incomplete records overview device snapshot is ignored', () async {
    SharedPreferences.setMockInitialValues({
      _snapshotKey('recordsOverview:2026'): jsonEncode({
        'savedAt': DateTime.utc(2026, 5, 20, 11, 50).toIso8601String(),
        'payload': {
          'season': 2026,
          'avgLeaders': [_leaderJson(metricKey: 'AVG')],
          'hrLeaders': const [],
          'opsLeaders': [_leaderJson(metricKey: 'OPS', value: '1.000')],
          'opsPlusLeaders': const [],
          'eraLeaders': const [],
          'todayHitter': {'label': '오늘의 타자'},
          'todayPitcher': {'label': '오늘의 투수'},
          'monthHitter': {'label': '이달의 타자'},
          'monthPitcher': {'label': '이달의 투수'},
        },
      }),
    });
    final repository = DeviceSnapshotPlayerRepository(
      primary: _ThrowingPlayerRepository(),
      fallback: _FallbackPlayerRepository(
        teamStats: _emptyStats(teamId: 'KT', season: 2026),
      ),
      now: () => DateTime.utc(2026, 5, 20, 12),
    );

    final overview = await repository.getRecordsOverview(season: 2026);

    expect(overview.avgLeaders, isEmpty);
    expect(overview.hrLeaders, isEmpty);
    expect(overview.opsLeaders, isEmpty);
    expect(overview.eraLeaders, isEmpty);
  });

  test(
    'historical incomplete records overview legacy snapshot is ignored',
    () async {
      SharedPreferences.setMockInitialValues({
        _snapshotKey('recordsOverview:2011'): jsonEncode({
          'season': 2011,
          'avgLeaders': [_leaderJson(metricKey: 'AVG')],
          'hrLeaders': [_leaderJson(metricKey: 'HR')],
          'opsLeaders': [_leaderJson(metricKey: 'OPS', value: '1.000')],
          'opsPlusLeaders': const [],
          'eraLeaders': const [],
          'todayHitter': {'label': '오늘의 타자'},
          'todayPitcher': {'label': '오늘의 투수'},
          'monthHitter': {'label': '이달의 타자'},
          'monthPitcher': {'label': '이달의 투수'},
        }),
      });
      final repository = DeviceSnapshotPlayerRepository(
        primary: _ThrowingPlayerRepository(),
        fallback: _FallbackPlayerRepository(
          teamStats: _emptyStats(teamId: 'KT', season: 2011),
        ),
        now: () => DateTime.utc(2026, 5, 20, 12),
      );

      final overview = await repository.getRecordsOverview(season: 2011);

      expect(overview.avgLeaders, isEmpty);
      expect(overview.hrLeaders, isEmpty);
      expect(overview.opsLeaders, isEmpty);
      expect(overview.eraLeaders, isEmpty);
    },
  );

  test('records overview snapshot with missing rank one is ignored', () async {
    SharedPreferences.setMockInitialValues({
      _snapshotKey('recordsOverview:2013'): jsonEncode({
        'season': 2013,
        'avgLeaders': [_leaderJson(rank: 2, metricKey: 'AVG')],
        'hrLeaders': [_leaderJson(rank: 2, metricKey: 'HR')],
        'opsLeaders': [_leaderJson(rank: 2, metricKey: 'OPS', value: '1.000')],
        'opsPlusLeaders': const [],
        'eraLeaders': [_leaderJson(rank: 2, metricKey: 'ERA', value: '2.88')],
        'todayHitter': {'label': '오늘의 타자'},
        'todayPitcher': {'label': '오늘의 투수'},
        'monthHitter': {'label': '이달의 타자'},
        'monthPitcher': {'label': '이달의 투수'},
      }),
    });
    final repository = DeviceSnapshotPlayerRepository(
      primary: _ThrowingPlayerRepository(),
      fallback: _FallbackPlayerRepository(
        teamStats: _emptyStats(teamId: 'KT', season: 2013),
      ),
      now: () => DateTime.utc(2026, 5, 20, 12),
    );

    final overview = await repository.getRecordsOverview(season: 2013);

    expect(overview.avgLeaders, isEmpty);
    expect(overview.hrLeaders, isEmpty);
    expect(overview.opsLeaders, isEmpty);
    expect(overview.eraLeaders, isEmpty);
  });

  test('previous records overview snapshot version is ignored', () async {
    SharedPreferences.setMockInitialValues({
      'player_snapshot:v2:recordsOverview:2013': jsonEncode({
        'season': 2013,
        'avgLeaders': [_leaderJson(rank: 2, metricKey: 'AVG')],
        'hrLeaders': [_leaderJson(rank: 2, metricKey: 'HR')],
        'opsLeaders': [_leaderJson(rank: 2, metricKey: 'OPS', value: '1.000')],
        'opsPlusLeaders': const [],
        'eraLeaders': [_leaderJson(rank: 2, metricKey: 'ERA', value: '2.88')],
        'todayHitter': {'label': '오늘의 타자'},
        'todayPitcher': {'label': '오늘의 투수'},
        'monthHitter': {'label': '이달의 타자'},
        'monthPitcher': {'label': '이달의 투수'},
      }),
    });
    final repository = DeviceSnapshotPlayerRepository(
      primary: _ThrowingPlayerRepository(),
      fallback: _FallbackPlayerRepository(
        teamStats: _emptyStats(teamId: 'KT', season: 2013),
      ),
      now: () => DateTime.utc(2026, 5, 20, 12),
    );

    final overview = await repository.getRecordsOverview(season: 2013);

    expect(overview.avgLeaders, isEmpty);
    expect(overview.hrLeaders, isEmpty);
    expect(overview.opsLeaders, isEmpty);
    expect(overview.eraLeaders, isEmpty);
  });

  test('leaderboard snapshot with missing rank one is ignored', () async {
    SharedPreferences.setMockInitialValues({
      _snapshotKey('leaderboard:avg:2013'): jsonEncode({
        'season': 2013,
        'leaders': [_leaderJson(rank: 2, metricKey: 'AVG')],
      }),
    });
    final repository = DeviceSnapshotPlayerRepository(
      primary: _ThrowingPlayerRepository(),
      fallback: _FallbackPlayerRepository(
        teamStats: _emptyStats(teamId: 'KT', season: 2013),
      ),
      now: () => DateTime.utc(2026, 5, 20, 12),
    );

    final leaders = await repository.getLeaderboard(
      season: 2013,
      metric: LeaderboardMetric.avg,
    );

    expect(leaders, isEmpty);
  });

  test('unsupported 2001 device snapshots are ignored', () async {
    SharedPreferences.setMockInitialValues({
      _snapshotKey('recordsOverview:2001'): jsonEncode({
        'savedAt': DateTime.utc(2026, 5, 20, 11, 50).toIso8601String(),
        'payload': {
          'season': 2001,
          'avgLeaders': [_leaderJson(metricKey: 'AVG')],
          'hrLeaders': [_leaderJson(metricKey: 'HR')],
          'opsLeaders': [_leaderJson(metricKey: 'OPS', value: '1.000')],
          'opsPlusLeaders': const [],
          'eraLeaders': [_leaderJson(metricKey: 'ERA', value: '2.88')],
          'todayHitter': {'label': '오늘의 타자'},
          'todayPitcher': {'label': '오늘의 투수'},
          'monthHitter': {'label': '이달의 타자'},
          'monthPitcher': {'label': '이달의 투수'},
        },
      }),
      _snapshotKey('leaderboard:avg:2001'): jsonEncode({
        'savedAt': DateTime.utc(2026, 5, 20, 11, 50).toIso8601String(),
        'payload': {
          'season': 2001,
          'leaders': [_leaderJson(metricKey: 'AVG')],
        },
      }),
      _snapshotKey('teamStats:LG:2001'): jsonEncode({
        'teamId': 'LG',
        'season': 2001,
        'hitting': {'AVG': '0.300'},
        'pitching': {'ERA': '3.00'},
      }),
    });
    final repository = DeviceSnapshotPlayerRepository(
      primary: _ThrowingPlayerRepository(),
      fallback: _FallbackPlayerRepository(
        teamStats: _emptyStats(teamId: 'LG', season: 2001),
      ),
      now: () => DateTime.utc(2026, 5, 20, 12),
    );

    final overview = await repository.getRecordsOverview(season: 2001);
    final leaders = await repository.getLeaderboard(
      season: 2001,
      metric: LeaderboardMetric.avg,
    );
    final stats = await repository.getTeamStats('LG', season: 2001);

    expect(overview.avgLeaders, isEmpty);
    expect(overview.hrLeaders, isEmpty);
    expect(overview.opsLeaders, isEmpty);
    expect(overview.eraLeaders, isEmpty);
    expect(leaders, isEmpty);
    expect(stats.season, 2001);
    expect(stats.hitting, isEmpty);
    expect(stats.pitching, isEmpty);
  });
}

TeamStats _emptyStats({required String teamId, required int season}) =>
    TeamStats(
      teamId: teamId,
      season: season,
      hitting: const {},
      pitching: const {},
    );

Map<String, Object> _leaderJson({
  int rank = 1,
  required String metricKey,
  String value = '1',
}) => {
  'rank': rank,
  'playerId': 'player-1',
  'playerType': 'hitter',
  'name': '테스트',
  'teamId': 'KT',
  'value': value,
  'metricKey': metricKey,
};

String _snapshotKey(String key) => 'player_snapshot:v3:$key';

class _ThrowingPlayerRepository implements PlayerRepository {
  @override
  Future<List<PlayerProfile>> getTeamPlayers(
    String teamId, {
    required int season,
  }) async {
    throw StateError('primary unavailable');
  }

  @override
  Future<PlayerProfile> getPlayerDetail(
    String playerId, {
    required int season,
  }) async {
    throw StateError('primary unavailable');
  }

  @override
  Future<TeamStats> getTeamStats(String teamId, {required int season}) async {
    throw StateError('primary unavailable');
  }

  @override
  Future<TeamRecordsBundle> getTeamRecords(
    String teamId, {
    required int season,
  }) async {
    throw StateError('primary unavailable');
  }

  @override
  Future<RecordsOverview> getRecordsOverview({required int season}) async {
    throw StateError('primary unavailable');
  }

  @override
  Future<List<RecordLeader>> getLeaderboard({
    required int season,
    required LeaderboardMetric metric,
  }) async {
    throw StateError('primary unavailable');
  }
}

class _FallbackPlayerRepository implements PlayerRepository {
  const _FallbackPlayerRepository({required this.teamStats});

  final TeamStats teamStats;

  @override
  Future<List<PlayerProfile>> getTeamPlayers(
    String teamId, {
    required int season,
  }) async => const [];

  @override
  Future<PlayerProfile> getPlayerDetail(
    String playerId, {
    required int season,
  }) async {
    throw StateError('fallback detail unavailable');
  }

  @override
  Future<TeamStats> getTeamStats(String teamId, {required int season}) async =>
      teamStats;

  @override
  Future<TeamRecordsBundle> getTeamRecords(
    String teamId, {
    required int season,
  }) async => TeamRecordsBundle(players: const [], teamStats: teamStats);

  @override
  Future<RecordsOverview> getRecordsOverview({required int season}) async =>
      RecordsOverview(
        season: season,
        avgLeaders: const [],
        hrLeaders: const [],
        opsLeaders: const [],
        opsPlusLeaders: const [],
        eraLeaders: const [],
        todayHitter: const FeaturedPlayerCard(label: '오늘의 타자'),
        todayPitcher: const FeaturedPlayerCard(label: '오늘의 투수'),
        monthHitter: const FeaturedPlayerCard(label: '이달의 타자'),
        monthPitcher: const FeaturedPlayerCard(label: '이달의 투수'),
      );

  @override
  Future<List<RecordLeader>> getLeaderboard({
    required int season,
    required LeaderboardMetric metric,
  }) async => const [];
}
