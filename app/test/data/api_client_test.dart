import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kbo_fans/data/api/api_client.dart';
import 'package:kbo_fans/data/models/records_overview.dart';
import 'package:kbo_fans/data/repositories/api_game_repository.dart';
import 'package:kbo_fans/data/repositories/api_home_repository.dart';
import 'package:kbo_fans/data/repositories/api_player_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'fresh-first API cache reuses fresh cache after request failure when explicitly allowed',
    () async {
      SharedPreferences.setMockInitialValues({
        'api_cache:scoreboard_home:2026-05-20': _cachedApiPayload({
          'source': 'fresh-cache',
        }, age: const Duration(seconds: 10)),
      });

      final client = ApiClient(
        dio: _dioWithAdapter(_FailingAdapter()),
        enableRequestTiming: false,
      );

      final data = await client.getCached(
        '/scoreboard/home',
        cacheKey: 'scoreboard_home:2026-05-20',
        maxAge: const Duration(seconds: 30),
        allowCacheOnFailure: true,
      );

      expect(data['source'], 'fresh-cache');
    },
  );

  test(
    'fresh-first API cache can surface failure instead of using fresh cache',
    () async {
      SharedPreferences.setMockInitialValues({
        'api_cache:scoreboard_home:2026-05-20': _cachedApiPayload({
          'source': 'fresh-cache',
        }, age: const Duration(seconds: 10)),
      });

      final client = ApiClient(
        dio: _dioWithAdapter(_FailingAdapter()),
        enableRequestTiming: false,
      );

      expect(
        () => client.getCached(
          '/scoreboard/home',
          cacheKey: 'scoreboard_home:2026-05-20',
          maxAge: const Duration(seconds: 30),
          allowCacheOnFailure: false,
        ),
        throwsA(isA<DioException>()),
      );
    },
  );

  test(
    'fresh-first API cache rejects stale cache after request failure',
    () async {
      SharedPreferences.setMockInitialValues({
        'api_cache:scoreboard_home:2026-05-20': _cachedApiPayload({
          'source': 'stale-cache',
        }, age: const Duration(minutes: 10)),
      });

      final client = ApiClient(
        dio: _dioWithAdapter(_FailingAdapter()),
        enableRequestTiming: false,
      );

      expect(
        () => client.getCached(
          '/scoreboard/home',
          cacheKey: 'scoreboard_home:2026-05-20',
          maxAge: const Duration(seconds: 30),
        ),
        throwsA(isA<DioException>()),
      );
    },
  );

  test('cached-first historical path may reuse stale cache', () async {
    SharedPreferences.setMockInitialValues({
      'api_cache:scoreboard_home:2026-05-01': _cachedApiPayload({
        'source': 'historical-cache',
      }, age: const Duration(days: 3)),
    });

    final client = ApiClient(
      dio: _dioWithAdapter(_FailingAdapter()),
      enableRequestTiming: false,
    );

    final data = await client.getCached(
      '/scoreboard/home',
      cacheKey: 'scoreboard_home:2026-05-01',
      preferCache: true,
      maxAge: const Duration(minutes: 5),
    );

    expect(data['source'], 'historical-cache');
  });

  test(
    'historical game cache avoids background refresh inside long TTL',
    () async {
      SharedPreferences.setMockInitialValues({
        'api_cache:scoreboard_home:2013-05-01': _cachedApiPayload({
          'games': const [],
        }, age: const Duration(days: 20)),
      });
      final adapter = _CountingSuccessAdapter({'games': const []});
      final repository = ApiGameRepository(
        ApiClient(dio: _dioWithAdapter(adapter), enableRequestTiming: false),
      );

      final games = await repository.getScoreboard('2013-05-01');
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(games, isEmpty);
      expect(adapter.calls, 0);
    },
  );

  test(
    'historical records overview cache avoids background refresh inside long TTL',
    () async {
      SharedPreferences.setMockInitialValues({
        'api_cache:recordsOverview:v5:2013': _cachedApiPayload(
          _recordsOverviewPayload(
            season: 2013,
            firstAvgRank: 1,
            firstEraRank: 1,
          ),
          age: const Duration(days: 30),
        ),
      });
      final adapter = _CountingSuccessAdapter(
        _recordsOverviewPayload(season: 2013, firstAvgRank: 1, firstEraRank: 1),
      );
      final repository = ApiPlayerRepository(
        ApiClient(dio: _dioWithAdapter(adapter), enableRequestTiming: false),
      );

      final overview = await repository.getRecordsOverview(season: 2013);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(overview.avgLeaders.first.rank, 1);
      expect(adapter.calls, 0);
    },
  );

  test('cached-first API cache ignores invalid cached payload', () async {
    SharedPreferences.setMockInitialValues({
      'api_cache:test_payload': _cachedApiPayload({
        'source': 'invalid-cache',
      }, age: const Duration(days: 3)),
    });

    final client = ApiClient(
      dio: _dioWithAdapter(_SuccessAdapter({'source': 'fresh'})),
      enableRequestTiming: false,
    );

    final data = await client.getCached(
      '/test',
      cacheKey: 'test_payload',
      preferCache: true,
      maxAge: const Duration(minutes: 5),
      isValid: (payload) => payload['source'] != 'invalid-cache',
    );

    expect(data['source'], 'fresh');
  });

  test('historical records overview ignores cached rank gaps', () async {
    SharedPreferences.setMockInitialValues({
      'api_cache:recordsOverview:v5:2013': _cachedApiPayload(
        _recordsOverviewPayload(season: 2013, firstAvgRank: 2, firstEraRank: 2),
        age: const Duration(days: 3),
      ),
    });
    final repository = ApiPlayerRepository(
      ApiClient(
        dio: _dioWithAdapter(
          _SuccessAdapter(
            _recordsOverviewPayload(
              season: 2013,
              firstAvgRank: 1,
              firstEraRank: 1,
            ),
          ),
        ),
        enableRequestTiming: false,
      ),
    );

    final overview = await repository.getRecordsOverview(season: 2013);

    expect(overview.avgLeaders.first.rank, 1);
    expect(overview.eraLeaders.first.rank, 1);
  });

  test('API player repository ignores unsupported 2001 cache', () async {
    SharedPreferences.setMockInitialValues({
      'api_cache:recordsOverview:v5:2001': _cachedApiPayload(
        _recordsOverviewPayload(season: 2001, firstAvgRank: 1, firstEraRank: 1),
        age: const Duration(days: 3),
      ),
      'api_cache:leaderboard:v3:avg:2001': _cachedApiPayload({
        'season': 2001,
        'metric': 'avg',
        'leaders': [_leader(rank: 1, metricKey: 'AVG', value: '0.350')],
      }, age: const Duration(days: 3)),
      'api_cache:teamStats:v2:LG:2001': _cachedApiPayload({
        'teamId': 'LG',
        'season': 2001,
        'hitting': {'AVG': '0.300'},
        'pitching': {'ERA': '3.00'},
      }, age: const Duration(days: 3)),
    });
    final repository = ApiPlayerRepository(
      ApiClient(
        dio: _dioWithAdapter(_FailingAdapter()),
        enableRequestTiming: false,
      ),
    );

    final overview = await repository.getRecordsOverview(season: 2001);
    final leaderboard = await repository.getLeaderboard(
      season: 2001,
      metric: LeaderboardMetric.avg,
    );
    final stats = await repository.getTeamStats('LG', season: 2001);

    expect(overview.avgLeaders, isEmpty);
    expect(overview.hrLeaders, isEmpty);
    expect(overview.opsLeaders, isEmpty);
    expect(overview.eraLeaders, isEmpty);
    expect(leaderboard, isEmpty);
    expect(stats.season, 2001);
    expect(stats.hitting, isEmpty);
    expect(stats.pitching, isEmpty);
  });

  test(
    'current scoreboard API failure is not masked by fresh API cache',
    () async {
      final today = _yyyyMmDd(DateTime.now());
      SharedPreferences.setMockInitialValues({
        'api_cache:scoreboard_home:$today': _cachedApiPayload({
          'games': const [],
        }, age: const Duration(seconds: 10)),
      });
      final repository = ApiGameRepository(
        ApiClient(
          dio: _dioWithAdapter(_FailingAdapter()),
          enableRequestTiming: false,
        ),
      );

      expect(
        () => repository.getScoreboard(today),
        throwsA(isA<DioException>()),
      );
    },
  );

  test('scoreboard parser keeps missing team totals unavailable', () async {
    SharedPreferences.setMockInitialValues({});
    final repository = ApiGameRepository(
      ApiClient(
        dio: _dioWithAdapter(
          _SuccessAdapter({
            'date': '2026-05-20',
            'games': [
              {
                'gameId': '20260520XXYY0',
                'status': 'LIVE',
                'inning': '8회초',
                'away': {
                  'teamId': 'XX',
                  'teamName': '원정',
                  'shortName': '원정',
                  'score': 2,
                  'scores': [
                    null,
                    null,
                    null,
                    null,
                    null,
                    null,
                    null,
                    null,
                    null,
                  ],
                  'hits': null,
                  'errors': null,
                  'balls': null,
                },
                'home': {
                  'teamId': 'YY',
                  'teamName': '홈',
                  'shortName': '홈',
                  'score': 1,
                  'scores': [
                    null,
                    null,
                    null,
                    null,
                    null,
                    null,
                    null,
                    null,
                    null,
                  ],
                  'hits': null,
                  'errors': null,
                  'balls': null,
                },
                'stadium': '잠실',
                'startTime': '18:30',
              },
            ],
          }),
        ),
        enableRequestTiming: false,
      ),
    );

    final games = await repository.getScoreboard('2026-05-20');

    expect(games.single.hasTeamStats, isFalse);
    expect(games.single.away.hits, 0);
    expect(games.single.home.walks, 0);
  });

  test('game lineup parser preserves row player id and image URL', () async {
    SharedPreferences.setMockInitialValues({});
    final repository = ApiGameRepository(
      ApiClient(
        dio: _dioWithAdapter(
          _SuccessAdapter({
            'gameId': '20260425LGOB0',
            'away': {
              'teamId': 'LG',
              'lineup': [
                {
                  'order': 4,
                  'position': '3B',
                  'positionKo': '3루수',
                  'name': '문보경',
                  'id': '69102',
                  'imageUrl': 'https://img.test/2026/69102.jpg',
                },
              ],
            },
            'home': {'teamId': 'OB', 'lineup': const []},
          }),
        ),
        enableRequestTiming: false,
      ),
    );

    final lineup = await repository.getLineupData('20260425LGOB0');

    expect(lineup.away.lineup.single.playerId, '69102');
    expect(
      lineup.away.lineup.single.imageUrl,
      'https://img.test/2026/69102.jpg',
    );
  });

  test('relay parser preserves current at-bat player image URLs', () async {
    SharedPreferences.setMockInitialValues({});
    final repository = ApiGameRepository(
      ApiClient(
        dio: _dioWithAdapter(
          _SuccessAdapter({
            'gameId': '20260425LGOB0',
            'currentAtBat': {
              'batter': {
                'name': '문보경',
                'imageUrl': 'https://img.test/2026/69102.jpg',
              },
              'pitcher': {
                'name': '최민석',
                'imageUrl': 'https://img.test/2026/55268.jpg',
              },
              'ballCount': {'balls': 1, 'strikes': 2, 'outs': 0},
            },
            'relayItems': const [],
          }),
        ),
        enableRequestTiming: false,
      ),
    );

    final relay = await repository.getRelayData('20260425LGOB0');

    expect(
      relay.currentAtBat?.batterImageUrl,
      'https://img.test/2026/69102.jpg',
    );
    expect(
      relay.currentAtBat?.pitcherImageUrl,
      'https://img.test/2026/55268.jpg',
    );
  });

  test('standings parser preserves team streak', () async {
    SharedPreferences.setMockInitialValues({});
    final repository = ApiGameRepository(
      ApiClient(
        dio: _dioWithAdapter(
          _SuccessAdapter({
            'season': 2026,
            'standings': [
              {
                'rank': 1,
                'teamId': 'LG',
                'teamName': 'LG 트윈스',
                'wins': 3,
                'losses': 0,
                'draws': 0,
                'pct': '1.000',
                'gb': '0',
                'streak': 'W3',
              },
            ],
          }),
        ),
        enableRequestTiming: false,
      ),
    );

    final standings = await repository.getStandings(2026);

    expect(standings.single.streak, 'W3');
    expect(standings.single.streakLabel, '3연승');
  });

  test('boxscore parser preserves extended batter and pitcher stats', () async {
    SharedPreferences.setMockInitialValues({});
    final repository = ApiGameRepository(
      ApiClient(
        dio: _dioWithAdapter(
          _SuccessAdapter({
            'gameId': '20260613KTLG0',
            'officialAvailable': true,
            'away': {
              'teamId': 'KT',
              'batters': [
                {
                  'order': 4,
                  'position': 'DH',
                  'name': '강백호',
                  'playerId': '50054',
                  'imageUrl': 'https://img.test/2026/50054.jpg',
                  'atBats': 4,
                  'runs': 2,
                  'hits': 3,
                  'rbi': 4,
                  'plateAppearances': 5,
                  'doubles': 1,
                  'triples': 0,
                  'homeRuns': 1,
                  'walks': 1,
                  'hitByPitch': 0,
                  'strikeouts': 1,
                  'stolenBases': 1,
                },
              ],
              'pitchers': [
                {
                  'name': '선발투수',
                  'playerId': '60123',
                  'imageUrl': 'https://img.test/2026/60123.jpg',
                  'innings': '5.2',
                  'hits': 4,
                  'strikeouts': 6,
                  'walks': 2,
                  'earnedRuns': 1,
                  'decision': 'W',
                  'pitchCount': 92,
                  'runs': 2,
                },
              ],
            },
            'home': {'teamId': 'LG', 'batters': const [], 'pitchers': const []},
          }),
        ),
        enableRequestTiming: false,
      ),
    );

    final boxscore = await repository.getBoxscoreData('20260613KTLG0');
    final batter = boxscore.away.batters.single;
    final pitcher = boxscore.away.pitchers.single;

    expect(batter.plateAppearances, 5);
    expect(batter.playerId, '50054');
    expect(batter.imageUrl, 'https://img.test/2026/50054.jpg');
    expect(batter.extraBaseHits, 2);
    expect(batter.slugging, 1.75);
    expect(batter.stolenBases, 1);
    expect(pitcher.pitchCount, 92);
    expect(pitcher.playerId, '60123');
    expect(pitcher.imageUrl, 'https://img.test/2026/60123.jpg');
    expect(pitcher.runs, 2);
    expect(pitcher.gameWhip, closeTo(1.06, 0.01));
  });

  test('home aggregate drops stale schedule remaining brief items', () async {
    SharedPreferences.setMockInitialValues({});
    final repository = ApiHomeRepository(
      ApiClient(
        dio: _dioWithAdapter(
          _SuccessAdapter({
            'date': '2026-06-19',
            'myTeam': 'LG',
            'myTeamBrief': null,
            'kboBrief': {
              'title': '오늘의 KBO 소식',
              'subtitle': '지금 볼 장면 2개',
              'items': [
                {
                  'type': 'big_match',
                  'eyebrow': '오늘 일정',
                  'title': '삼성 vs LG',
                  'subtitle': '18:30 · 잠실 · 오늘 2경기 예정',
                  'route': '/game/20260619SSLG0',
                },
                {
                  'type': 'schedule_remaining',
                  'eyebrow': '남은 경기',
                  'title': 'SSG vs 두산 외 1경기',
                  'subtitle': '18:30 시작 · 중계 바로가기',
                  'route': '/schedule',
                },
              ],
            },
            'quickItems': [],
            'standingsPreview': [],
          }),
        ),
        enableRequestTiming: false,
      ),
    );

    final aggregate = await repository.getHomeAggregate(
      date: '2026-06-19',
      myTeam: 'LG',
    );

    expect(aggregate.kboBrief!.items.map((item) => item.type), ['big_match']);
  });

  test(
    'current standings API failure is not masked by fresh API cache or app bootstrap',
    () async {
      final season = DateTime.now().year;
      SharedPreferences.setMockInitialValues({
        'api_cache:standings:$season': _cachedApiPayload({
          'standings': [
            {
              'rank': 1,
              'teamId': 'KT',
              'teamName': 'KT',
              'wins': 1,
              'losses': 0,
              'draws': 0,
              'pct': '1.000',
              'gb': '0',
            },
          ],
        }, age: const Duration(seconds: 10)),
      });
      final repository = ApiGameRepository(
        ApiClient(
          dio: _dioWithAdapter(_FailingAdapter()),
          enableRequestTiming: false,
        ),
      );

      expect(
        () => repository.getStandings(season),
        throwsA(isA<DioException>()),
      );
    },
  );

  test(
    'current records overview API failure is not masked by fresh API cache or app bootstrap',
    () {
      final season = DateTime.now().year;
      SharedPreferences.setMockInitialValues({
        'api_cache:recordsOverview:v5:$season': _cachedApiPayload(
          _recordsOverviewPayload(
            season: season,
            firstAvgRank: 1,
            firstEraRank: 1,
          ),
          age: const Duration(seconds: 10),
        ),
      });
      final repository = ApiPlayerRepository(
        ApiClient(
          dio: _dioWithAdapter(_FailingAdapter()),
          enableRequestTiming: false,
        ),
      );

      expect(
        () => repository.getRecordsOverview(season: season),
        throwsA(isA<DioException>()),
      );
    },
  );

  test(
    'current leaderboard API failure is not masked by fresh API cache or app bootstrap',
    () {
      final season = DateTime.now().year;
      SharedPreferences.setMockInitialValues({
        'api_cache:leaderboard:v3:avg:$season': _cachedApiPayload({
          'season': season,
          'metric': 'avg',
          'leaders': [_leader(rank: 1, metricKey: 'AVG', value: '0.350')],
        }, age: const Duration(seconds: 10)),
      });
      final repository = ApiPlayerRepository(
        ApiClient(
          dio: _dioWithAdapter(_FailingAdapter()),
          enableRequestTiming: false,
        ),
      );

      expect(
        () => repository.getLeaderboard(
          season: season,
          metric: LeaderboardMetric.avg,
        ),
        throwsA(isA<DioException>()),
      );
    },
  );
}

String _cachedApiPayload(Map<String, dynamic> data, {required Duration age}) =>
    jsonEncode({
      'cachedAt': DateTime.now().toUtc().subtract(age).toIso8601String(),
      'data': data,
    });

String _yyyyMmDd(DateTime value) {
  final year = value.year.toString().padLeft(4, '0');
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}

Dio _dioWithAdapter(HttpClientAdapter adapter) {
  final dio = Dio(BaseOptions(baseUrl: 'https://example.test/api'));
  dio.httpClientAdapter = adapter;
  return dio;
}

class _FailingAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    throw DioException(
      requestOptions: options,
      type: DioExceptionType.connectionError,
      message: 'offline',
    );
  }

  @override
  void close({bool force = false}) {}
}

class _SuccessAdapter implements HttpClientAdapter {
  _SuccessAdapter(this.data);

  final Map<String, dynamic> data;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      jsonEncode({
        'success': true,
        'data': data,
        'error': null,
        'timestamp': DateTime.utc(2026, 5, 20).toIso8601String(),
      }),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _CountingSuccessAdapter extends _SuccessAdapter {
  _CountingSuccessAdapter(super.data);

  int calls = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    calls += 1;
    return super.fetch(options, requestStream, cancelFuture);
  }
}

Map<String, dynamic> _recordsOverviewPayload({
  required int season,
  required int firstAvgRank,
  required int firstEraRank,
}) => {
  'season': season,
  'leaders': {
    'avg': [_leader(rank: firstAvgRank, metricKey: 'AVG', value: '0.348')],
    'hr': [_leader(rank: 1, metricKey: 'HR', value: '37')],
    'ops': [_leader(rank: 1, metricKey: 'OPS', value: '1.039')],
    'opsPlus': const [],
    'era': [_leader(rank: firstEraRank, metricKey: 'ERA', value: '2.48')],
  },
  'featured': {
    'todayHitter': {'label': '오늘의 타자'},
    'todayPitcher': {'label': '오늘의 투수'},
    'monthHitter': {'label': '이달의 타자'},
    'monthPitcher': {'label': '이달의 투수'},
  },
};

Map<String, dynamic> _leader({
  required int rank,
  required String metricKey,
  required String value,
}) => {
  'rank': rank,
  'playerId': 'player-$rank',
  'playerType': metricKey == 'ERA' ? 'pitcher' : 'hitter',
  'name': '테스트$rank',
  'teamId': 'KT',
  'value': value,
  'metricKey': metricKey,
};
