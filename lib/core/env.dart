import 'package:flutter/foundation.dart';

/// API origin. Override at build/run time:
/// `flutter run --dart-define=API_URL=https://your-api.example.com`
class AppEnv {
  static const String apiUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: '',
  );

  static String resolveApiBaseUrl() {
    if (apiUrl.isNotEmpty) return apiUrl.replaceAll(RegExp(r'/$'), '');
    if (kIsWeb) return 'http://localhost:5000';
    if (defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:5000';
    }
    return 'http://localhost:5000';
  }
}
