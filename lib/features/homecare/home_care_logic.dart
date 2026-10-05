/// Town match for the "Near you" label.
/// Empty town never matches. Comparison is case-insensitive and does not use GPS.
bool homeCareLocationNearTown(String? location, String? town) {
  final needle = town?.trim().toLowerCase() ?? '';
  if (needle.isEmpty) return false;
  return (location ?? '').toLowerCase().contains(needle);
}

int homeCareStatusRank(String status) {
  switch (status) {
    case 'open':
      return 0;
    case 'claimed':
      return 1;
    default:
      return 2;
  }
}

String? formatHomeCareWhen(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  final parsed = DateTime.tryParse(raw.trim());
  if (parsed == null) return null;
  final local = parsed.toLocal();
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final hour12 = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final minute = local.minute.toString().padLeft(2, '0');
  final suffix = local.hour >= 12 ? 'PM' : 'AM';
  return '${local.day} ${months[local.month - 1]} ${local.year}, $hour12:$minute $suffix';
}

final _homeCareShareToken = RegExp(r'^[A-Za-z0-9_-]{16,128}$');
final _homeCareDigitsOnly = RegExp(r'^\d+$');
final _homeCareJobLink = RegExp(
  r'https://healynks\.app/homecare/([A-Za-z0-9_-]{16,128})',
);

/// Share tokens are unguessable. A raw numeric id is not a job link.
bool homeCareShareTokenOk(String? token) {
  final value = token?.trim() ?? '';
  if (!_homeCareShareToken.hasMatch(value)) return false;
  if (_homeCareDigitsOnly.hasMatch(value)) return false;
  return true;
}

/// Pulls the share token out of an in-app notification or SMS body.
String? homeCareTokenFromNotification(String? text) {
  final token = _homeCareJobLink.firstMatch(text ?? '')?.group(1);
  if (!homeCareShareTokenOk(token)) return null;
  return token;
}

/// `/homecare/<token>` only. Other paths, including a numeric id or another site, are ignored.
String? homeCareJobPath(String? raw) {
  if (raw == null) return null;
  final value = raw.trim();
  if (value.isEmpty) return null;
  if (value.contains('://') || value.startsWith('//') || value.contains('\\') || value.contains('@')) {
    return null;
  }
  final uri = Uri.tryParse(value);
  if (uri == null || uri.hasScheme || uri.hasAuthority) return null;
  final match = RegExp(r'^/homecare/([A-Za-z0-9_-]{16,128})$').firstMatch(uri.path);
  final token = match?.group(1);
  if (!homeCareShareTokenOk(token)) return null;
  return '/homecare/$token';
}

/// Full public URL. Never the API host, even when the app is served from there.
String? homeCarePublicUrl(String? token) {
  if (!homeCareShareTokenOk(token)) return null;
  return 'https://healynks.app/homecare/${token!.trim()}';
}

String homeCareRoleLabel(String role) {
  switch (role) {
    case 'admin':
      return 'Admin';
    case 'agency':
      return 'Agency';
    case 'nurse':
      return 'Nurse';
    default:
      final cleaned = role.trim();
      if (cleaned.isEmpty) return 'Caregiver';
      return cleaned[0].toUpperCase() + cleaned.substring(1);
  }
}
