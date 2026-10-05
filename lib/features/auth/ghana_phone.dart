/// Ghana mobile numbers: 0XXXXXXXXX, 233XXXXXXXXX, +233…, or 9 national digits.
String? normalizeGhanaPhone(String raw) {
  var d = raw.trim().replaceAll(RegExp(r'[\s\-().]'), '');
  if (d.startsWith('+')) d = d.substring(1);
  if (!RegExp(r'^\d+$').hasMatch(d)) return null;
  if (d.startsWith('233') && d.length == 12) {
    d = '0${d.substring(3)}';
  } else if (d.length == 9) {
    d = '0$d';
  }
  if (!RegExp(r'^0\d{9}$').hasMatch(d)) return null;
  return d;
}

/// Ghana numbers stay in the local 0XXXXXXXXX form.
/// Any other number must be E.164: a leading + and 8–15 digits.
String? normalizeAccountPhone(String raw) {
  final ghana = normalizeGhanaPhone(raw);
  if (ghana != null) return ghana;
  final compact = raw.trim().replaceAll(RegExp(r'[\s\-().]'), '');
  if (!compact.startsWith('+')) return null;
  final digits = compact.substring(1);
  if (!RegExp(r'^\d{8,15}$').hasMatch(digits)) return null;
  if (digits.startsWith('233')) return null;
  return '+$digits';
}
