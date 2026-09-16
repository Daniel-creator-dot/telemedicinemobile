import 'package:flutter/foundation.dart';

/// API origin. Override at build/run time:
/// `flutter run --dart-define=API_URL=http://localhost:5000`
///
/// Physical Android/iOS **must** pass `--dart-define=API_URL=http://<PC_LAN_IP>:5000`.
/// Without it, release/profile builds hit [liveApiUrl] (Render). Debug native builds
/// default to the Android emulator loopback (`10.0.2.2`) so they never silently
/// use a broken production host — pass API_URL for a real phone.
class AppEnv {
  static const String liveApiUrl = 'https://telemedicine-server-l2bj.onrender.com';

  static const String apiUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: '',
  );

  static String resolveApiBaseUrl() {
    if (apiUrl.isNotEmpty) return apiUrl.replaceAll(RegExp(r'/$'), '');
    // Local web serve (e.g. http://localhost:8081) must hit the local API,
    // not production — otherwise booking slots/login hit the wrong backend.
    if (kIsWeb) {
      final host = Uri.base.host;
      if (host == 'localhost' || host == '127.0.0.1') {
        return 'http://localhost:5000';
      }
    }
    // Debug on device/emulator: prefer emulator host mapping over Render so
    // "cannot reach server" is local and [debugHostHint] shows a real URL.
    if (kDebugMode && !kIsWeb) {
      return 'http://10.0.2.2:5000';
    }
    return liveApiUrl;
  }

  static bool get isLocalOverride {
    final resolved = resolveApiBaseUrl().toLowerCase();
    if (resolved.contains('localhost') ||
        resolved.contains('127.0.0.1') ||
        resolved.contains('10.0.2.2')) {
      return true;
    }
    // Private LAN ranges when API_URL is set for a physical phone.
    return RegExp(
      r'https?://(192\.168\.|10\.|172\.(1[6-9]|2\d|3[01])\.)',
    ).hasMatch(resolved);
  }

  /// Shown on login in debug, or whenever [apiUrl] was set via dart-define.
  static String get debugHostHint {
    if (kDebugMode || apiUrl.isNotEmpty) return resolveApiBaseUrl();
    return '';
  }
}
