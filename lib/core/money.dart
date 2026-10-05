/// Patient-facing money from a server payload.
/// Labels are computed on the server from CF-IPCountry. The raw fee stays in GHS.
String moneyLabel(Map? data, String field, {Object? fallbackAmount}) {
  if (data != null) {
    final label = data['${field}_label']?.toString();
    if (label != null && label.trim().isNotEmpty) return label.trim();
    final currency = (data['currency']?.toString() ?? 'GHS').toUpperCase();
    if (currency == 'USD') {
      final display = data['${field}_display'];
      if (display != null) return formatMoneyAmount(display, currency: 'USD');
    }
    final raw = data[field] ?? fallbackAmount;
    if (raw != null) return formatMoneyAmount(raw, currency: 'GHS');
  }
  if (fallbackAmount != null) return formatMoneyAmount(fallbackAmount, currency: 'GHS');
  return 'GHS 0';
}

String formatMoneyAmount(Object? amount, {String? currency, String? label}) {
  if (label != null && label.trim().isNotEmpty) return label.trim();
  final n = amount is num ? amount.toDouble() : double.tryParse('${amount ?? ''}') ?? 0;
  if ((currency ?? 'GHS').toUpperCase() == 'USD') {
    return '\$${n.toStringAsFixed(2)}';
  }
  final whole = (n - n.round()).abs() < 0.001;
  return whole ? 'GHS ${n.round()}' : 'GHS ${n.toStringAsFixed(2)}';
}
