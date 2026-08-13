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
