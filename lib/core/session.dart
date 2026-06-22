import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/auth_user.dart';
import 'api_client.dart';

const _kToken = 'graprime_token';
const _kUser = 'graprime_user';

class Session extends ChangeNotifier {
  Session(this._api);

  final ApiClient _api;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  String? _token;
  AuthUser? _user;
  bool _restoring = true;

  String? get token => _token;
  AuthUser? get user => _user;
  bool get isAuthenticated => _token != null && _user != null;
  bool get isRestoring => _restoring;

  Future<void> restore() async {
    try {
      final token = await _storage.read(key: _kToken);
      final userJson = await _storage.read(key: _kUser);
      if (token != null && userJson != null) {
        _token = token;
        _user = AuthUser.fromJson(
          jsonDecode(userJson) as Map<String, dynamic>,
        );
        _api.setToken(token);
      }
    } catch (e) {
      debugPrint('Session restore failed: $e');
      await clear();
    } finally {
      _restoring = false;
      notifyListeners();
    }
  }

  Future<void> setSession({
    required String token,
    required AuthUser user,
  }) async {
    _token = token;
    _user = user;
    _restoring = false;
    _api.setToken(token);
    await _storage.write(key: _kToken, value: token);
    await _storage.write(key: _kUser, value: jsonEncode(user.toJson()));
    notifyListeners();
  }

  Future<void> clear() async {
    _token = null;
    _user = null;
    _api.setToken(null);
    await _storage.delete(key: _kToken);
    await _storage.delete(key: _kUser);
    notifyListeners();
  }

  void patchUser(AuthUser user) {
    _user = user;
    _storage.write(key: _kUser, value: jsonEncode(user.toJson()));
    notifyListeners();
  }
}
