import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/config/app_config.dart';
import '../../core/utils/kbo_time.dart';
import '../../core/widgets/dev_console.dart';

class ApiClient {
  late final Dio _dio;
  static const _requestTimeout = Duration(seconds: 25);
  static const _defaultMaxGetAttempts = 2;
  static const _defaultRetryDelay = Duration(milliseconds: 250);
  static const _cachePrefix = 'api_cache:';
  static const _maxCacheStorageKeyBytes = 192;
  static const _maxCacheEntries = 64;
  static const _maxCacheEntryBytes = 256 * 1024;
  static const _maxCacheTotalBytes = 2 * 1024 * 1024;
  static Future<void> _cacheMutationQueue = Future<void>.value();
  final Duration _requestDeadline;
  final int _maxGetAttempts;
  final Duration _retryDelay;

  ApiClient({
    Dio? dio,
    bool enableRequestTiming = true,
    Duration requestDeadline = _requestTimeout,
    int maxGetAttempts = _defaultMaxGetAttempts,
    Duration retryDelay = _defaultRetryDelay,
  }) : _requestDeadline = requestDeadline,
       _maxGetAttempts = maxGetAttempts,
       _retryDelay = retryDelay {
    if (requestDeadline.inMicroseconds <= 0) {
      throw ArgumentError.value(
        requestDeadline,
        'requestDeadline',
        'must be greater than zero',
      );
    }
    if (maxGetAttempts < 1) {
      throw ArgumentError.value(
        maxGetAttempts,
        'maxGetAttempts',
        'must be at least one',
      );
    }
    if (retryDelay.isNegative) {
      throw ArgumentError.value(
        retryDelay,
        'retryDelay',
        'must not be negative',
      );
    }
    _dio =
        dio ??
        Dio(
          BaseOptions(
            baseUrl: AppConfig.instance.apiBaseUrl,
            // KBO 원본 크롤링을 경유하는 일부 응답은 10초를 넘길 수 있어 웹에서 조기 타임아웃이 자주 났다.
            connectTimeout: _requestTimeout,
            sendTimeout: _requestTimeout,
            receiveTimeout: _requestTimeout,
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
          ),
        );

    if (enableRequestTiming) {
      _dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            options.extra['request_started_at'] =
                DateTime.now().microsecondsSinceEpoch;
            handler.next(options);
          },
          onResponse: (response, handler) {
            _logRequestTiming(response.requestOptions, response.statusCode);
            handler.next(response);
          },
          onError: (error, handler) {
            _logRequestTiming(
              error.requestOptions,
              error.response?.statusCode,
              failed: true,
            );
            handler.next(error);
          },
        ),
      );
    }

    if (dio == null && !AppConfig.instance.isLocal) {
      _dio.interceptors.add(
        LogInterceptor(
          requestBody: !AppConfig.instance.isRelease,
          responseBody: !AppConfig.instance.isRelease,
          error: true,
          logPrint: (obj) {
            if (!AppConfig.instance.isRelease) {
              // ignore: avoid_print
              print(obj);
            }
          },
        ),
      );
    }
  }

  /// GET 요청 → ApiEnvelope.data 반환
  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    final elapsed = Stopwatch()..start();
    for (var attempt = 1; attempt <= _maxGetAttempts; attempt += 1) {
      final remaining = _requestDeadline - elapsed.elapsed;
      if (remaining.inMicroseconds <= 0) {
        throw _requestDeadlineException(
          RequestOptions(path: path, queryParameters: queryParameters),
        );
      }

      try {
        final response = await _getWithinDeadline(
          path,
          queryParameters: queryParameters,
          remaining: remaining,
        );
        return _extractData(response);
      } on DioException catch (error) {
        final canRetry =
            attempt < _maxGetAttempts && _isTransientGetFailure(error);
        if (!canRetry) {
          rethrow;
        }

        final nextDelay = _retryDelayFor(error);
        final retryBudget = _requestDeadline - elapsed.elapsed;
        if (retryBudget.inMicroseconds <= nextDelay.inMicroseconds) {
          rethrow;
        }
        if (nextDelay > Duration.zero) {
          await Future<void>.delayed(nextDelay);
        }
      }
    }

    throw StateError('unreachable GET attempt state');
  }

  Future<Response<Map<String, dynamic>>> _getWithinDeadline(
    String path, {
    Map<String, dynamic>? queryParameters,
    required Duration remaining,
  }) async {
    final cancelToken = CancelToken();
    return _dio
        .get<Map<String, dynamic>>(
          path,
          queryParameters: queryParameters,
          cancelToken: cancelToken,
        )
        .timeout(
          remaining,
          onTimeout: () {
            cancelToken.cancel('API request deadline exceeded');
            throw _requestDeadlineException(
              cancelToken.requestOptions ??
                  RequestOptions(path: path, queryParameters: queryParameters),
            );
          },
        );
  }

  bool _isTransientGetFailure(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.connectionError:
        return true;
      case DioExceptionType.badResponse:
        return switch (error.response?.statusCode) {
          408 || 429 || 502 || 503 || 504 => true,
          _ => false,
        };
      case DioExceptionType.badCertificate:
      case DioExceptionType.cancel:
      case DioExceptionType.unknown:
        return false;
    }
  }

  Duration _retryDelayFor(DioException error) {
    final retryAfter = error.response?.headers.value('retry-after')?.trim();
    final retryAfterSeconds = int.tryParse(retryAfter ?? '');
    if (retryAfterSeconds == null || retryAfterSeconds < 0) {
      return _retryDelay;
    }
    final serverDelay = Duration(seconds: retryAfterSeconds);
    return serverDelay > _retryDelay ? serverDelay : _retryDelay;
  }

  DioException _requestDeadlineException(RequestOptions requestOptions) {
    return DioException(
      requestOptions: requestOptions,
      type: DioExceptionType.receiveTimeout,
      message: 'API request exceeded ${_requestDeadline.inMilliseconds}ms',
    );
  }

  Future<Map<String, dynamic>> getCached(
    String path, {
    Map<String, dynamic>? queryParameters,
    required String cacheKey,
    bool preferCache = false,
    Duration? maxAge,
    bool Function(Map<String, dynamic> data)? isValid,
    bool Function(Map<String, dynamic> data)? isCacheable,
    bool allowCacheOnFailure = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final storageKey = '$_cachePrefix$cacheKey';
    final persistsResponse = _shouldPersistResponse(
      path,
      cacheKey: cacheKey,
      queryParameters: queryParameters,
    );
    if (!persistsResponse && prefs.containsKey(storageKey)) {
      await _removeCachedPayload(prefs, storageKey);
    }
    var cached = persistsResponse
        ? _readCachedPayload(prefs, storageKey)
        : null;
    if (cached != null &&
        ((isValid != null && !isValid(cached.data)) ||
            (isCacheable != null && !isCacheable(cached.data)))) {
      await _removeCachedPayload(prefs, storageKey);
      cached = null;
    }
    if (cached != null && cached.cachedAt.isAfter(DateTime.now().toUtc())) {
      cached = null;
    }
    final isFresh = cached != null && _isCacheFresh(cached, maxAge);

    if (preferCache && cached != null && isFresh) {
      return cached.data;
    }

    if (preferCache && cached != null) {
      if (!isFresh) {
        unawaited(
          _refreshCached(
            path,
            queryParameters: queryParameters,
            prefs: prefs,
            storageKey: storageKey,
            isValid: isValid,
            isCacheable: isCacheable,
          ),
        );
      }
      return cached.data;
    }

    try {
      final fresh = await get(path, queryParameters: queryParameters);
      if (isValid != null && !isValid(fresh)) {
        throw StateError('Invalid API cache payload for $cacheKey');
      }
      if (persistsResponse && (isCacheable == null || isCacheable(fresh))) {
        await _writeCachedPayload(prefs, storageKey, fresh);
      } else if (prefs.containsKey(storageKey)) {
        await _removeCachedPayload(prefs, storageKey);
      }
      return fresh;
    } catch (_) {
      if (allowCacheOnFailure && cached != null && isFresh) {
        return cached.data;
      }
      rethrow;
    }
  }

  /// POST 요청 → ApiEnvelope.data 반환
  Future<Map<String, dynamic>> post(String path, {Object? data}) async {
    final response = await _dio.post<Map<String, dynamic>>(path, data: data);
    return _extractData(response);
  }

  Future<void> postClientMetric(Map<String, dynamic> data) async {
    if (AppConfig.instance.isLocal) {
      return;
    }
    try {
      await post('/metrics/client', data: data);
    } catch (_) {
      if (kDebugMode && !AppConfig.instance.isLocal) {
        DevConsole.instance.warn('client metric send failed');
      }
    }
  }

  Future<List<String>> diagnoseTeamRecords({
    required String teamId,
    required int season,
  }) async {
    final diagnostics = <String>[];
    final targets = [
      ('team/players', '/team/$teamId/players', {'season': season}),
      ('team/stats', '/team/$teamId/stats', {'season': season}),
      ('team/records', '/team/$teamId/records', {'season': season}),
    ];

    for (final target in targets) {
      final startedAt = DateTime.now().microsecondsSinceEpoch;
      try {
        final data = await get(target.$2, queryParameters: target.$3);
        final elapsedMs =
            (DateTime.now().microsecondsSinceEpoch - startedAt) / 1000;
        final summary = switch (target.$1) {
          'team/players' =>
            'players=${(data['players'] as List<dynamic>? ?? const []).length}',
          'team/stats' =>
            'hitting=${(data['hitting'] as Map<String, dynamic>? ?? const {}).length}',
          'team/records' =>
            'players=${(data['players'] as List<dynamic>? ?? const []).length}, stats=${(data['teamStats'] as Map<String, dynamic>? ?? const {}).length}',
          _ => 'ok',
        };
        diagnostics.add(
          'DIAG ${target.$1} OK ${elapsedMs.toStringAsFixed(0)}ms [$summary]',
        );
      } catch (error) {
        final elapsedMs =
            (DateTime.now().microsecondsSinceEpoch - startedAt) / 1000;
        diagnostics.add(
          'DIAG ${target.$1} FAIL ${elapsedMs.toStringAsFixed(0)}ms [${describeAsyncError(error)}]',
        );
      }
    }

    return diagnostics;
  }

  /// 백엔드 ApiEnvelope 구조에서 data 필드 추출
  Map<String, dynamic> _extractData(Response<Map<String, dynamic>> response) {
    final body = response.data;
    if (body == null) {
      throw DioException(
        requestOptions: response.requestOptions,
        message: 'Empty response',
      );
    }

    final success = body['success'] as bool? ?? false;
    if (!success) {
      final error = body['error'] as Map<String, dynamic>?;
      final code = error?['code'] ?? 'UNKNOWN';
      final message = error?['message'] ?? 'Unknown error';
      throw ApiException(code: code.toString(), message: message.toString());
    }

    return body['data'] as Map<String, dynamic>? ?? {};
  }

  _CachedPayload? _readCachedPayload(
    SharedPreferences prefs,
    String storageKey,
  ) {
    final raw = prefs.get(storageKey);
    if (raw is! String || raw.isEmpty) {
      return null;
    }
    if (_utf8Bytes(storageKey) > _maxCacheStorageKeyBytes ||
        _cacheEntryBytes(storageKey, raw) > _maxCacheEntryBytes) {
      return null;
    }

    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final cachedAt = decoded['cachedAt'] as String?;
      final payload = decoded['data'];
      final parsedCachedAt = cachedAt == null
          ? null
          : DateTime.tryParse(cachedAt)?.toUtc();
      if (payload is Map<String, dynamic> && parsedCachedAt != null) {
        return _CachedPayload(data: payload, cachedAt: parsedCachedAt);
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  Future<void> _writeCachedPayload(
    SharedPreferences prefs,
    String storageKey,
    Map<String, dynamic> data,
  ) async {
    final encoded = jsonEncode({
      'cachedAt': DateTime.now().toUtc().toIso8601String(),
      'data': data,
    });
    final storageKeyBytes = _utf8Bytes(storageKey);
    final entryBytes = _cacheEntryBytes(storageKey, encoded);
    if (storageKeyBytes > _maxCacheStorageKeyBytes ||
        entryBytes > _maxCacheEntryBytes ||
        entryBytes > _maxCacheTotalBytes) {
      await _removeCachedPayload(prefs, storageKey);
      return;
    }

    await _enqueueCacheMutation(() async {
      final entries = <_CacheEntryMetadata>[];
      for (final key in prefs.getKeys()) {
        if (!key.startsWith(_cachePrefix) || key == storageKey) {
          continue;
        }
        final value = prefs.get(key);
        if (value is! String) {
          await prefs.remove(key);
          continue;
        }
        entries.add(_cacheEntryMetadata(key, value));
      }

      entries.sort((left, right) {
        if (left.isWithinLimits != right.isWithinLimits) {
          return left.isWithinLimits ? 1 : -1;
        }
        final timestampOrder = left.cachedAt.compareTo(right.cachedAt);
        return timestampOrder != 0
            ? timestampOrder
            : left.storageKey.compareTo(right.storageKey);
      });

      var entryCount = entries.length + 1;
      var totalBytes = entryBytes;
      for (final entry in entries) {
        totalBytes += entry.bytes;
      }
      for (final entry in entries) {
        final mustEvict =
            !entry.isWithinLimits ||
            entryCount > _maxCacheEntries ||
            totalBytes > _maxCacheTotalBytes;
        if (!mustEvict) {
          continue;
        }
        await prefs.remove(entry.storageKey);
        entryCount -= 1;
        totalBytes -= entry.bytes;
      }

      if (entryCount <= _maxCacheEntries && totalBytes <= _maxCacheTotalBytes) {
        await prefs.setString(storageKey, encoded);
      }
    });
  }

  Future<void> _refreshCached(
    String path, {
    required SharedPreferences prefs,
    required String storageKey,
    Map<String, dynamic>? queryParameters,
    bool Function(Map<String, dynamic> data)? isValid,
    bool Function(Map<String, dynamic> data)? isCacheable,
  }) async {
    try {
      final fresh = await get(path, queryParameters: queryParameters);
      if (isValid != null && !isValid(fresh)) {
        return;
      }
      if (isCacheable == null || isCacheable(fresh)) {
        await _writeCachedPayload(prefs, storageKey, fresh);
      } else {
        await _removeCachedPayload(prefs, storageKey);
      }
    } catch (_) {
      // Cached-first paths should remain silent on refresh failure.
    }
  }

  bool _isCacheFresh(_CachedPayload cached, Duration? maxAge) {
    if (maxAge == null) {
      return false;
    }
    final age = DateTime.now().toUtc().difference(cached.cachedAt);
    return !age.isNegative && age <= maxAge;
  }

  bool _shouldPersistResponse(
    String path, {
    required String cacheKey,
    Map<String, dynamic>? queryParameters,
  }) {
    if (path == '/home' ||
        path == '/scoreboard/home' ||
        path == '/scoreboard/compact') {
      final date =
          queryParameters?['date']?.toString() ??
          RegExp(r'\d{4}-\d{2}-\d{2}').firstMatch(cacheKey)?.group(0) ??
          '';
      return isHistoricalKboDate(date);
    }

    final gameMatch = RegExp(r'^/game/(\d{8})[^/]*(?:/.*)?$').firstMatch(path);
    if (gameMatch != null) {
      final compactDate = gameMatch.group(1)!;
      final date =
          '${compactDate.substring(0, 4)}-'
          '${compactDate.substring(4, 6)}-'
          '${compactDate.substring(6, 8)}';
      return isHistoricalKboDate(date);
    }

    if (path == '/schedule') {
      final month =
          queryParameters?['month']?.toString() ??
          RegExp(r'\d{4}-\d{2}').firstMatch(cacheKey)?.group(0) ??
          '';
      return isHistoricalKboMonth(month);
    }

    if (path == '/standings' ||
        path.startsWith('/records/') ||
        path.startsWith('/team/') ||
        path.startsWith('/player/')) {
      final season = int.tryParse(
        queryParameters?['season']?.toString() ??
            RegExp(r'(\d{4})$').firstMatch(cacheKey)?.group(1) ??
            '',
      );
      return season != null && season < kboCurrentSeason();
    }

    return true;
  }

  Future<void> _removeCachedPayload(
    SharedPreferences prefs,
    String storageKey,
  ) {
    return _enqueueCacheMutation(() => prefs.remove(storageKey));
  }

  Future<void> _enqueueCacheMutation(Future<void> Function() mutation) {
    final operation = _cacheMutationQueue.then((_) => mutation());
    _cacheMutationQueue = operation.catchError((Object _) {});
    return operation;
  }

  void _logRequestTiming(
    RequestOptions options,
    int? statusCode, {
    bool failed = false,
  }) {
    final startedAt = options.extra['request_started_at'] as int?;
    if (startedAt == null || AppConfig.instance.isRelease) {
      return;
    }
    if (failed && options.path == '/metrics/client') {
      return;
    }

    final elapsedMs =
        (DateTime.now().microsecondsSinceEpoch - startedAt) / 1000;
    final message =
        'API ${failed ? 'FAIL' : 'OK'} ${options.method} ${options.path} '
        '${elapsedMs.toStringAsFixed(0)}ms'
        '${statusCode != null ? ' [$statusCode]' : ''}';
    if (failed) {
      DevConsole.instance.warn(message);
    } else {
      DevConsole.instance.info(message);
    }
  }
}

class _CachedPayload {
  final Map<String, dynamic> data;
  final DateTime cachedAt;

  const _CachedPayload({required this.data, required this.cachedAt});
}

class _CacheEntryMetadata {
  final String storageKey;
  final int bytes;
  final DateTime cachedAt;
  final bool isWithinLimits;

  const _CacheEntryMetadata({
    required this.storageKey,
    required this.bytes,
    required this.cachedAt,
    required this.isWithinLimits,
  });
}

_CacheEntryMetadata _cacheEntryMetadata(String storageKey, String encoded) {
  DateTime? cachedAt;
  var hasValidShape = false;
  try {
    final decoded = jsonDecode(encoded);
    if (decoded is Map<String, dynamic>) {
      cachedAt = DateTime.tryParse(
        decoded['cachedAt']?.toString() ?? '',
      )?.toUtc();
      hasValidShape =
          cachedAt != null && decoded['data'] is Map<String, dynamic>;
    }
  } catch (_) {
    // Malformed entries are evicted before valid cache entries.
  }
  final bytes = _cacheEntryBytes(storageKey, encoded);
  return _CacheEntryMetadata(
    storageKey: storageKey,
    bytes: bytes,
    cachedAt: cachedAt ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    isWithinLimits:
        hasValidShape &&
        _utf8Bytes(storageKey) <= ApiClient._maxCacheStorageKeyBytes &&
        bytes <= ApiClient._maxCacheEntryBytes,
  );
}

int _cacheEntryBytes(String storageKey, String encoded) =>
    _utf8Bytes(storageKey) + _utf8Bytes(encoded);

int _utf8Bytes(String value) => utf8.encode(value).length;

class ApiException implements Exception {
  final String code;
  final String message;
  const ApiException({required this.code, required this.message});

  @override
  String toString() => 'ApiException($code): $message';
}

String describeAsyncError(Object error) {
  if (error is ApiException) {
    return '서버 응답을 처리하지 못했습니다. 잠시 후 다시 시도해주세요.';
  }

  if (error is DioException) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
        return '응답이 지연되고 있습니다. 잠시 후 다시 시도해주세요.';
      case DioExceptionType.connectionError:
        return '서버 연결에 실패했습니다. 네트워크 또는 백엔드 상태를 확인해주세요.';
      case DioExceptionType.badResponse:
        return '서버 오류가 발생했습니다. 잠시 후 다시 시도해주세요.';
      case DioExceptionType.cancel:
        return '요청이 취소되었습니다.';
      case DioExceptionType.badCertificate:
      case DioExceptionType.unknown:
        return '일시적인 오류가 발생했습니다. 다시 시도해주세요.';
    }
  }

  return '데이터를 불러오지 못했습니다. 잠시 후 다시 시도해주세요.';
}
