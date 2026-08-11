import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kbo_fans/core/utils/kbo_time.dart';
import 'package:kbo_fans/data/api/api_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'current relay boxscore and lineup are not persisted and legacy entries are removed',
    () async {
      final gameId = '${kboDateKey().replaceAll('-', '')}LGKT0';
      final targets = {
        '/game/$gameId/relay': 'relay:$gameId:',
        '/game/$gameId/boxscore': 'boxscore:$gameId',
        '/game/$gameId/lineup': 'lineup:$gameId',
      };
      SharedPreferences.setMockInitialValues({
        for (final cacheKey in targets.values)
          'api_cache:$cacheKey': _cachedPayload({'legacy': true}),
      });
      final client = ApiClient(
        dio: _dioWithAdapter(
          _SuccessAdapter({
            'gameId': gameId,
            'currentAtBat': null,
            'relayItems': const [],
          }),
        ),
        enableRequestTiming: false,
      );

      for (final target in targets.entries) {
        await client.getCached(target.key, cacheKey: target.value);
      }

      final prefs = await SharedPreferences.getInstance();
      for (final cacheKey in targets.values) {
        expect(prefs.containsKey('api_cache:$cacheKey'), isFalse);
      }
    },
  );

  test('historical relay remains persisted and cached-first', () async {
    const gameId = '20130501KTLG0';
    const storageKey = 'api_cache:relay:$gameId:';
    SharedPreferences.setMockInitialValues({});
    final freshClient = ApiClient(
      dio: _dioWithAdapter(
        _SuccessAdapter({
          'gameId': gameId,
          'currentAtBat': null,
          'relayItems': const [],
        }),
      ),
      enableRequestTiming: false,
    );

    await freshClient.getCached(
      '/game/$gameId/relay',
      cacheKey: 'relay:$gameId:',
      preferCache: true,
      maxAge: const Duration(days: 30),
    );
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey(storageKey), isTrue);

    final cachedClient = ApiClient(
      dio: _dioWithAdapter(_FailingAdapter()),
      enableRequestTiming: false,
    );
    final cached = await cachedClient.getCached(
      '/game/$gameId/relay',
      cacheKey: 'relay:$gameId:',
      preferCache: true,
      maxAge: const Duration(days: 30),
    );

    expect(cached['gameId'], gameId);
  });

  test('cache rejects oversized storage keys and entries', () async {
    SharedPreferences.setMockInitialValues({});
    final client = ApiClient(
      dio: _dioWithAdapter(_SuccessAdapter({'value': 'small'})),
      enableRequestTiming: false,
    );
    final oversizedKey = List.filled(200, 'k').join();

    await client.getCached('/test', cacheKey: oversizedKey);

    final oversizedClient = ApiClient(
      dio: _dioWithAdapter(
        _SuccessAdapter({'value': List.filled(300 * 1024, 'x').join()}),
      ),
      enableRequestTiming: false,
    );
    await oversizedClient.getCached('/test', cacheKey: 'oversized-entry');

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('api_cache:$oversizedKey'), isFalse);
    expect(prefs.containsKey('api_cache:oversized-entry'), isFalse);
  });

  test(
    'oversized fresh historical response evicts the stale entry for the same key',
    () async {
      const gameId = '20130501KTLG0';
      const cacheKey = 'relay:$gameId:';
      const storageKey = 'api_cache:$cacheKey';
      SharedPreferences.setMockInitialValues({
        storageKey: jsonEncode({
          'cachedAt': DateTime.utc(2013, 5, 1).toIso8601String(),
          'data': const {'gameId': gameId, 'version': 'stale'},
        }),
      });
      final client = ApiClient(
        dio: _dioWithAdapter(
          _SuccessAdapter({
            'gameId': gameId,
            'version': 'fresh',
            'relayText': List.filled(300 * 1024, 'x').join(),
          }),
        ),
        enableRequestTiming: false,
      );

      final fresh = await client.getCached(
        '/game/$gameId/relay',
        cacheKey: cacheKey,
      );

      expect(fresh['version'], 'fresh');
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.containsKey(storageKey),
        isFalse,
        reason: 'an unpersistable fresh response must not leave stale data',
      );
    },
  );

  test('a cache write always evicts malformed legacy entries', () async {
    SharedPreferences.setMockInitialValues({
      'api_cache:malformed-json': '{',
      'api_cache:malformed-shape': jsonEncode({
        'cachedAt': DateTime.now().toUtc().toIso8601String(),
        'data': const <Object>[],
      }),
    });
    final client = ApiClient(
      dio: _dioWithAdapter(_SuccessAdapter({'value': 'fresh'})),
      enableRequestTiming: false,
    );

    await client.getCached('/test', cacheKey: 'fresh-entry');

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('api_cache:malformed-json'), isFalse);
    expect(prefs.containsKey('api_cache:malformed-shape'), isFalse);
    expect(prefs.containsKey('api_cache:fresh-entry'), isTrue);
  });

  test('cache evicts the oldest entry above the 64 entry limit', () async {
    SharedPreferences.setMockInitialValues({});
    final client = ApiClient(
      dio: _dioWithAdapter(_SuccessAdapter({'value': 'small'})),
      enableRequestTiming: false,
    );

    for (var index = 0; index < 65; index += 1) {
      await client.getCached(
        '/test',
        cacheKey: 'entry:${index.toString().padLeft(2, '0')}',
      );
    }

    final prefs = await SharedPreferences.getInstance();
    final cacheKeys = prefs.getKeys().where(
      (key) => key.startsWith('api_cache:'),
    );
    expect(cacheKeys.length, 64);
    expect(prefs.containsKey('api_cache:entry:00'), isFalse);
    expect(prefs.containsKey('api_cache:entry:64'), isTrue);
  });

  test(
    'cache evicts oldest entries above the 2 MiB total byte limit',
    () async {
      SharedPreferences.setMockInitialValues({});
      final payload = {'value': List.filled(245000, 'x').join()};
      final client = ApiClient(
        dio: _dioWithAdapter(_SuccessAdapter(payload)),
        enableRequestTiming: false,
      );

      for (var index = 0; index < 9; index += 1) {
        await client.getCached(
          '/test',
          cacheKey: 'large:${index.toString().padLeft(2, '0')}',
        );
      }

      final prefs = await SharedPreferences.getInstance();
      final cacheKeys = prefs.getKeys().where(
        (key) => key.startsWith('api_cache:'),
      );
      final totalBytes = cacheKeys.fold<int>(0, (sum, key) {
        final value = prefs.getString(key)!;
        return sum + utf8.encode(key).length + utf8.encode(value).length;
      });
      expect(cacheKeys.length, 8);
      expect(totalBytes, lessThanOrEqualTo(2 * 1024 * 1024));
      expect(prefs.containsKey('api_cache:large:00'), isFalse);
      expect(prefs.containsKey('api_cache:large:08'), isTrue);
    },
  );
}

String _cachedPayload(Map<String, dynamic> data) => jsonEncode({
  'cachedAt': DateTime.now().toUtc().toIso8601String(),
  'data': data,
});

Dio _dioWithAdapter(HttpClientAdapter adapter) {
  final dio = Dio(BaseOptions(baseUrl: 'https://example.test/api'));
  dio.httpClientAdapter = adapter;
  return dio;
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
        'timestamp': DateTime.now().toUtc().toIso8601String(),
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
