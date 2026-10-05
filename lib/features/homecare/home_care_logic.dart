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
