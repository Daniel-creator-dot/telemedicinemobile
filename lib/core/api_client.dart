import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'env.dart';

typedef UnauthorizedHandler = void Function();

class ApiClient {
  static String get defaultBaseUrl => AppEnv.resolveApiBaseUrl();

  ApiClient() {
    _dio = Dio(
      BaseOptions(
        baseUrl: defaultBaseUrl,
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
          debugPrint('[API] ${options.method} ${options.uri.path}');
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
      debugPrint('[API] Session token attached');
    }
  }

  static String messageFromDio(DioException err, [String fallback = 'Something went wrong']) {
    final data = err.response?.data;
    if (data is Map) {
      final m = data['message'] ?? data['error'];
      if (m != null && m.toString().trim().isNotEmpty) {
        final cleaned = hideApiOrigin(m.toString(), '');
        if (cleaned.isNotEmpty) return cleaned;
      }
    }
    switch (err.type) {
      case DioExceptionType.connectionError:
      case DioExceptionType.connectionTimeout:
        return 'Cannot reach Healynks right now. Check your connection and try again.';
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
        return 'Healynks took too long to respond. Check your connection and try again.';
      case DioExceptionType.badResponse:
        final status = err.response?.statusCode ?? 0;
        if (status == 401) return 'Those details do not match an account.';
        if (status == 403) return 'You do not have access to do that.';
        if (status == 404) return 'We could not find that.';
        if (status == 429) return 'Too many attempts. Wait a moment and try again.';
        if (status >= 500) return 'Healynks could not complete that. Try again in a moment.';
        return fallback;
      default:
        return hideApiOrigin(err.message ?? fallback, fallback);
    }
  }

  /// Dio messages often embed the request URL. Keep that off the screen.
  static String hideApiOrigin(String message, [String fallback = 'Something went wrong']) {
    final lower = message.toLowerCase();
    if (lower.contains('onrender.com') ||
        lower.contains('telemedicine-server') ||
        lower.contains('http://') ||
        lower.contains('https://') ||
        lower.contains('xmlhttprequest') ||
        lower.contains('socketexception') ||
        lower.contains('dioexception') ||
        lower.contains('clientexception')) {
      return fallback;
    }
    return message;
  }
}
