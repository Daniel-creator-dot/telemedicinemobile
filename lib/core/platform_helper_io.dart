import 'dart:io' show Platform;

// Platform helper for mobile (dart:io available)
class PlatformHelper {
  static bool get isIOS => Platform.isIOS;
  static bool get isAndroid => Platform.isAndroid;
}
