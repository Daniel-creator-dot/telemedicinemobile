import '../../models/auth_user.dart';

String paystackPaymentEmail(AuthUser user) {
  final username = user.username.trim();
  if (username.contains('@')) return username;
  final digits = user.phoneNumber?.replaceAll(RegExp(r'\D'), '') ?? username.replaceAll(RegExp(r'\D'), '');
  if (digits.length >= 9) return 'patient$digits@digihealth.app';
  return 'patient${user.id.replaceAll('-', '').substring(0, 12)}@digihealth.app';
}

String? extractPaystackReference(Uri uri) {
  final ref = uri.queryParameters['reference']?.trim() ??
      uri.queryParameters['trxref']?.trim();
  if (ref != null && ref.isNotEmpty) return ref;
  return null;
}

bool isPaystackCallbackUrl(String url) {
  final lower = url.toLowerCase();
  return lower.contains('reference=') ||
      lower.contains('trxref=') ||
      lower.contains('/paystack/callback');
}
