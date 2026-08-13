import 'package:flutter/foundation.dart';

/// API origin. Override at build/run time:
/// `flutter run --dart-define=API_URL=http://localhost:5000`
class AppEnv {
  static const String liveApiUrl = 'https://telemedicine-server-l2bj.onrender.com';

  static const String apiUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: '',
  );

  static String resolveApiBaseUrl() {
    if (apiUrl.isNotEmpty) return apiUrl.replaceAll(RegExp(r'/$'), '');
    return liveApiUrl;
  }

  static bool get isLocalOverride =>
      apiUrl.isNotEmpty && (apiUrl.contains('localhost') || apiUrl.contains('127.0.0.1') || apiUrl.contains('10.0.2.2'));

  static String get debugHostHint => kDebugMode ? resolveApiBaseUrl() : '';
}
