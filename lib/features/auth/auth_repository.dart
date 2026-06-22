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

  Future<void> register({
    required String username,
    required String password,
    required String name,
    required String phoneNumber,
    required String email,
  }) async {
    await _api.dio.post<Map<String, dynamic>>(
      '/api/auth/register',
      data: {
        'username': username.trim(),
        'password': password,
        'name': name.trim(),
        'phone_number': phoneNumber.trim(),
        'email': email.trim(),
      },
    );
    // Registration endpoint also returns token/user in Graprime backend
    // but the screen flow can login immediately or we parse it
    // Wait, the backend index.ts says:
    // res.status(201).json({ token, user: { id: user.id, username: user.username, role: user.role, name } });
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
