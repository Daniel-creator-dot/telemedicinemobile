DateTime? parseAppointmentDate(String raw) {
  try {
    return DateTime.parse(raw.split('T').first);
  } catch (_) {}
  const months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];
  final parts = raw.replaceAll(',', '').split(' ');
  if (parts.length == 3) {
    final mi = months.indexWhere((m) => m.toLowerCase() == parts[0].toLowerCase());
    if (mi != -1) {
      return DateTime(int.parse(parts[2]), mi + 1, int.parse(parts[1]));
    }
  }
  return null;
}

String monthName(int m) {
  const names = [
    '', 'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];
  return names[m];
}

int compareAppointmentDates(String a, String b, {bool descending = false}) {
  final da = parseAppointmentDate(a);
  final db = parseAppointmentDate(b);
  if (da == null && db == null) return 0;
  if (da == null) return 1;
  if (db == null) return -1;
  return descending ? db.compareTo(da) : da.compareTo(db);
}
