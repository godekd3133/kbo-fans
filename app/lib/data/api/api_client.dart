import 'package:dio/dio.dart';
import '../../core/config/app_config.dart';

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
}

class ApiException implements Exception {
  final String code;
  final String message;
  const ApiException({required this.code, required this.message});

  @override
  String toString() => 'ApiException($code): $message';
}
