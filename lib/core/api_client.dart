import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

typedef UnauthorizedHandler = void Function();

class ApiClient {
  ApiClient() {
    _dio = Dio(
      BaseOptions(
        baseUrl: 'http://localhost:5000',
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 30),
        followRedirects: true,
        maxRedirects: 5,
        headers: {'Content-Type': 'application/json'},
      ),
    );
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          debugPrint('[API] Request: ${options.method} ${options.uri}');
          debugPrint('[API] Headers: ${options.headers}');
          handler.next(options);
        },
        onResponse: (response, handler) {
          debugPrint('[API] Response: ${response.statusCode} ${response.requestOptions.uri}');
          handler.next(response);
        },
        onError: (err, handler) {
          final status = err.response?.statusCode;
          debugPrint('[API] Error: ${status} ${err.requestOptions.uri}');
          debugPrint('[API] Error response: ${err.response?.data}');
          // Only logout on 401 (unauthorized), not 403 (forbidden)
          // 403 can mean authenticated but lacking permission for specific resource
          if (status == 401) {
            onUnauthorized?.call();
          }
          handler.next(err);
        },
      ),
    );
  }

  late final Dio _dio;
  UnauthorizedHandler? onUnauthorized;

  Dio get dio => _dio;

  void setToken(String? token) {
    if (token == null || token.isEmpty) {
      _dio.options.headers.remove('Authorization');
      debugPrint('[API] Token removed');
    } else {
      _dio.options.headers['Authorization'] = 'Bearer $token';
      debugPrint('[API] Token set: Bearer ${token.substring(0, 10)}...');
    }
    debugPrint('[API] Current headers: ${_dio.options.headers}');
  }

  static String messageFromDio(DioException err, [String fallback = 'Something went wrong']) {
    final data = err.response?.data;
    if (data is Map) {
      final m = data['message'] ?? data['error'];
      if (m != null) return m.toString();
    }
    if (err.type == DioExceptionType.connectionError ||
        err.type == DioExceptionType.connectionTimeout) {
      return 'Cannot reach the server. Check your internet connection.';
    }
    return err.message ?? fallback;
  }
}
