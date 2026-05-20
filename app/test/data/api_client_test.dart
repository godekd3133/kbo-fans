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
