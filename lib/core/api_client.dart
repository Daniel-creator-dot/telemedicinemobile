import 'package:dio/dio.dart';

typedef UnauthorizedHandler = void Function();

class ApiClient {
  ApiClient() {
    _dio = Dio(
      BaseOptions(
        baseUrl: 'https://graprimeback-wniz.onrender.com',
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 30),
        followRedirects: true,
        maxRedirects: 5,
        headers: {'Content-Type': 'application/json'},
      ),
    );
    _dio.interceptors.add(
      InterceptorsWrapper(
        onError: (err, handler) {
          final status = err.response?.statusCode;
          if (status == 401 || status == 403) {
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
    } else {
      _dio.options.headers['Authorization'] = 'Bearer $token';
    }
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
