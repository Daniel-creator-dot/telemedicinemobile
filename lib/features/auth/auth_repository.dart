import 'package:dio/dio.dart';
import '../../core/api_client.dart';
import '../../models/auth_user.dart';

class AuthResult {
  const AuthResult({required this.user, required this.token});
  final AuthUser user;
  final String token;
}

class AuthRepository {
  AuthRepository(this._api);

  final ApiClient _api;

  Future<AuthResult> login({
    required String username,
    required String password,
  }) async {
    final res = await _api.dio.post<Map<String, dynamic>>(
      '/api/auth/login',
      data: {
        'username': username.trim(),
        'password': password,
      },
    );
    return _parseAuthResponse(res.data);
  }

  Future<String?> requestOtp({required String phone, required String purpose}) async {
    final res = await _api.dio.post<Map<String, dynamic>>(
      '/api/auth/request-otp',
      data: {'phone': phone.trim(), 'purpose': purpose},
    );
    return res.data?['debug_otp']?.toString();
  }

  Future<AuthResult> registerWithOtp({
    required String phone,
    required String code,
    required String password,
    required String name,
    required String email,
    required bool telemedicineConsent,
    required bool privacyConsent,
    required bool communicationConsent,
  }) async {
    final res = await _api.dio.post<Map<String, dynamic>>(
      '/api/auth/register-otp',
      data: {
        'phone': phone.trim(),
        'code': code.trim(),
        'password': password,
        'name': name.trim(),
        'email': email.trim(),
        'consents': [
          {'type': 'telemedicine', 'accepted': telemedicineConsent},
          {'type': 'data_processing', 'accepted': privacyConsent},
          {'type': 'communication', 'accepted': communicationConsent},
        ],
      },
    );
    return _parseAuthResponse(res.data);
  }

  Future<void> forgotPassword(String username) async {
    await _api.dio.post<Map<String, dynamic>>(
      '/api/auth/forgot-password',
      data: {'username': username.trim()},
    );
  }

  Future<void> resetPassword({
    required String username,
    required String code,
    required String newPassword,
  }) async {
    await _api.dio.post<Map<String, dynamic>>(
      '/api/auth/reset-password',
      data: {
        'username': username.trim(),
        'code': code.trim(),
        'newPassword': newPassword,
      },
    );
  }

  AuthResult _parseAuthResponse(Map<String, dynamic>? data) {
    if (data == null) throw Exception('Empty auth response');
    final token = data['token']?.toString();
    final userJson = data['user'];
    if (token == null || userJson is! Map) {
      throw Exception('Invalid auth response');
    }
    return AuthResult(
      token: token,
      user: AuthUser.fromJson(Map<String, dynamic>.from(userJson)),
    );
  }

  static String errorMessage(Object err) {
    if (err is DioException) {
      return ApiClient.messageFromDio(err, 'Authentication failed');
    }
    if (err is Exception) return err.toString().replaceFirst('Exception: ', '');
    return err.toString();
  }
}
