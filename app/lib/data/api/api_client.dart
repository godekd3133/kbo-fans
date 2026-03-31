import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/config/app_config.dart';
import '../../core/widgets/dev_console.dart';

class ApiClient {
  late final Dio _dio;
  static const _requestTimeout = Duration(seconds: 25);
  static const _cachePrefix = 'api_cache:';

  ApiClient() {
    _dio = Dio(
      BaseOptions(
        baseUrl: AppConfig.instance.apiBaseUrl,
        // KBO 원본 크롤링을 경유하는 일부 응답은 10초를 넘길 수 있어 웹에서 조기 타임아웃이 자주 났다.
        connectTimeout: _requestTimeout,
        receiveTimeout: _requestTimeout,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );

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

    _dio.interceptors.add(
      LogInterceptor(
        requestBody: !AppConfig.instance.isRelease,
        responseBody: !AppConfig.instance.isRelease,
        error: true,
        logPrint: (obj) {
          // Release에서는 로그 출력 안 함
          if (!AppConfig.instance.isRelease) {
            // ignore: avoid_print
            print(obj);
          }
        },
      ),
    );
  }

  /// GET 요청 → ApiEnvelope.data 반환
  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      path,
      queryParameters: queryParameters,
    );
    return _extractData(response);
  }

  Future<Map<String, dynamic>> getCached(
    String path, {
    Map<String, dynamic>? queryParameters,
    required String cacheKey,
    bool preferCache = false,
    Duration? maxAge,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final storageKey = '$_cachePrefix$cacheKey';
    final cached = _readCachedPayload(prefs, storageKey);
    final isFresh = cached != null && _isCacheFresh(cached, maxAge);

    if (cached != null && isFresh) {
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
          ),
        );
      }
      return cached.data;
    }

    try {
      final fresh = await get(path, queryParameters: queryParameters);
      await _writeCachedPayload(prefs, storageKey, fresh);
      return fresh;
    } catch (_) {
      if (cached != null) {
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
    if (!kIsWeb && AppConfig.instance.isLocal) {
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
    final raw = prefs.getString(storageKey);
    if (raw == null || raw.isEmpty) {
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
      'cachedAt': DateTime.now().toIso8601String(),
      'data': data,
    });
    await prefs.setString(storageKey, encoded);
  }

  Future<void> _refreshCached(
    String path, {
    required SharedPreferences prefs,
    required String storageKey,
    Map<String, dynamic>? queryParameters,
  }) async {
    try {
      final fresh = await get(path, queryParameters: queryParameters);
      await _writeCachedPayload(prefs, storageKey, fresh);
    } catch (_) {
      // Cached-first paths should remain silent on refresh failure.
    }
  }

  bool _isCacheFresh(_CachedPayload cached, Duration? maxAge) {
    if (maxAge == null) {
      return false;
    }
    return DateTime.now().toUtc().difference(cached.cachedAt) <= maxAge;
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

  const _CachedPayload({
    required this.data,
    required this.cachedAt,
  });
}

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
