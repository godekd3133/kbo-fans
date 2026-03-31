import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../core/config/app_config.dart';
import '../../core/widgets/dev_console.dart';

class ApiClient {
  late final Dio _dio;
  static const _requestTimeout = Duration(seconds: 25);

  ApiClient() {
    _dio = Dio(BaseOptions(
      baseUrl: AppConfig.instance.apiBaseUrl,
      // KBO 원본 크롤링을 경유하는 일부 응답은 10초를 넘길 수 있어 웹에서 조기 타임아웃이 자주 났다.
      connectTimeout: _requestTimeout,
      receiveTimeout: _requestTimeout,
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    ));

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          options.extra['request_started_at'] = DateTime.now().microsecondsSinceEpoch;
          handler.next(options);
        },
        onResponse: (response, handler) {
          _logRequestTiming(response.requestOptions, response.statusCode);
          handler.next(response);
        },
        onError: (error, handler) {
          _logRequestTiming(error.requestOptions, error.response?.statusCode, failed: true);
          handler.next(error);
        },
      ),
    );

    _dio.interceptors.add(LogInterceptor(
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
    ));
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

  /// POST 요청 → ApiEnvelope.data 반환
  Future<Map<String, dynamic>> post(
    String path, {
    Object? data,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      path,
      data: data,
    );
    return _extractData(response);
  }

  Future<void> postClientMetric(Map<String, dynamic> data) async {
    try {
      await post('/metrics/client', data: data);
    } catch (_) {
      if (kDebugMode) {
        DevConsole.instance.warn('client metric send failed');
      }
    }
  }

  /// 백엔드 ApiEnvelope 구조에서 data 필드 추출
  Map<String, dynamic> _extractData(Response<Map<String, dynamic>> response) {
    final body = response.data;
    if (body == null) throw DioException(requestOptions: response.requestOptions, message: 'Empty response');

    final success = body['success'] as bool? ?? false;
    if (!success) {
      final error = body['error'] as Map<String, dynamic>?;
      final code = error?['code'] ?? 'UNKNOWN';
      final message = error?['message'] ?? 'Unknown error';
      throw ApiException(code: code.toString(), message: message.toString());
    }

    return body['data'] as Map<String, dynamic>? ?? {};
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

    final elapsedMs =
        (DateTime.now().microsecondsSinceEpoch - startedAt) / 1000;
    final level = failed ? DevConsole.instance.warn : DevConsole.instance.info;
    level(
      'API ${options.method} ${options.path} ${elapsedMs.toStringAsFixed(0)}ms'
      '${statusCode != null ? ' [$statusCode]' : ''}',
    );
  }
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
