/// +2348031234567 → 0803 123 4567, the way Nigerians write their numbers.
String displayPhone(String? e164) {
  if (e164 == null || e164.isEmpty) return '';
  if (e164.startsWith('+234') && e164.length == 14) {
    final n = '0${e164.substring(4)}';
    return '${n.substring(0, 4)} ${n.substring(4, 7)} ${n.substring(7)}';
  }
  return e164;
}

/// "just now", "5 min ago", "3 h ago", "2 days ago".
String timeAgo(DateTime at) {
  final d = DateTime.now().difference(at);
  if (d.inMinutes < 1) return 'just now';
  if (d.inHours < 1) return '${d.inMinutes} min ago';
  if (d.inDays < 1) return '${d.inHours} h ago';
  if (d.inDays == 1) return 'yesterday';
  return '${d.inDays} days ago';
}

/// 12 Oct 2026, 14:05 in the phone's time zone.
String dateTime(DateTime at) {
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final l = at.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${l.day} ${months[l.month - 1]} ${l.year}, ${two(l.hour)}:${two(l.minute)}';
}

/// VINs are 19 letters and digits; people type them with spaces or dashes.
String? normalizeVin(String input) {
  final v = input.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();
  return v.isEmpty ? null : v;
}

bool isValidVin(String vin) => RegExp(r'^[0-9A-Z]{19}$').hasMatch(vin);
