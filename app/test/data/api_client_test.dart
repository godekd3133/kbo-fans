import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kbo_fans/data/api/api_client.dart';
import 'package:kbo_fans/data/models/records_overview.dart';
import 'package:kbo_fans/data/repositories/api_game_repository.dart';
import 'package:kbo_fans/data/repositories/api_player_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'fresh-first API cache reuses only fresh cache after request failure',
    () async {
      SharedPreferences.setMockInitialValues({
        'api_cache:scoreboard_home:2026-05-20': jsonEncode({
          'cachedAt': DateTime.now()
              .toUtc()
              .subtract(const Duration(seconds: 10))
              .toIso8601String(),
          'data': {'source': 'fresh-cache'},
        }),
      });

      final client = ApiClient(
        dio: _dioWithAdapter(_FailingAdapter()),
        enableRequestTiming: false,
      );

      final data = await client.getCached(
        '/scoreboard/home',
        cacheKey: 'scoreboard_home:2026-05-20',
        maxAge: const Duration(seconds: 30),
      );

      expect(data['source'], 'fresh-cache');
    },
  );

  test(
    'fresh-first API cache rejects stale cache after request failure',
    () async {
      SharedPreferences.setMockInitialValues({
        'api_cache:scoreboard_home:2026-05-20': jsonEncode({
          'cachedAt': DateTime.now()
              .toUtc()
              .subtract(const Duration(minutes: 10))
              .toIso8601String(),
          'data': {'source': 'stale-cache'},
        }),
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
      'api_cache:scoreboard_home:2026-05-01': jsonEncode({
        'cachedAt': DateTime.now()
            .toUtc()
            .subtract(const Duration(days: 3))
            .toIso8601String(),
        'data': {'source': 'historical-cache'},
      }),
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

  test('cached-first API cache ignores invalid cached payload', () async {
    SharedPreferences.setMockInitialValues({
      'api_cache:test_payload': jsonEncode({
        'cachedAt': DateTime.now()
            .toUtc()
            .subtract(const Duration(days: 3))
            .toIso8601String(),
        'data': {'source': 'invalid-cache'},
      }),
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
      'api_cache:recordsOverview:v4:2013': jsonEncode({
        'cachedAt': DateTime.now()
            .toUtc()
            .subtract(const Duration(days: 3))
            .toIso8601String(),
        'data': _recordsOverviewPayload(
          season: 2013,
          firstAvgRank: 2,
          firstEraRank: 2,
        ),
      }),
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

  test(
    'current standings API failure is not masked by app bootstrap',
    () async {
      SharedPreferences.setMockInitialValues({});
      final repository = ApiGameRepository(
        ApiClient(
          dio: _dioWithAdapter(_FailingAdapter()),
          enableRequestTiming: false,
        ),
      );

      expect(
        () => repository.getStandings(DateTime.now().year),
        throwsA(isA<DioException>()),
      );
    },
  );

  test(
    'current records overview API failure is not masked by app bootstrap',
    () {
      SharedPreferences.setMockInitialValues({});
      final repository = ApiPlayerRepository(
        ApiClient(
          dio: _dioWithAdapter(_FailingAdapter()),
          enableRequestTiming: false,
        ),
      );

      expect(
        () => repository.getRecordsOverview(season: DateTime.now().year),
        throwsA(isA<DioException>()),
      );
    },
  );

  test('current leaderboard API failure is not masked by app bootstrap', () {
    SharedPreferences.setMockInitialValues({});
    final repository = ApiPlayerRepository(
      ApiClient(
        dio: _dioWithAdapter(_FailingAdapter()),
        enableRequestTiming: false,
      ),
    );

    expect(
      () => repository.getLeaderboard(
        season: DateTime.now().year,
        metric: LeaderboardMetric.avg,
      ),
      throwsA(isA<DioException>()),
    );
  });
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
