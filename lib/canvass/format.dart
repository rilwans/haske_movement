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

/// 15 Dec 2026.
String shortDate(DateTime d) {
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${d.day} ${months[d.month - 1]} ${d.year}';
}

/// 12 Oct 2026, 14:05 in the phone's time zone.
String dateTime(DateTime at) {
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final l = at.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${l.day} ${months[l.month - 1]} ${l.year}, ${two(l.hour)}:${two(l.minute)}';
}

/// VINs are 6 to 30 letters and digits; people type them with spaces or dashes.
String? normalizeVin(String input) {
  final v = input.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();
  return v.isEmpty ? null : v;
}

bool isValidVin(String vin) => RegExp(r'^[0-9A-Z]{6,30}$').hasMatch(vin);

/// A year of birth as typed, or null if blank.
int? parseBirthYear(String input) => int.tryParse(input.trim());

/// The check erims makes: a year from 1900 to this one.
String? birthYearError(String? input) {
  final t = (input ?? '').trim();
  if (t.isEmpty) return null;
  final y = int.tryParse(t);
  final now = DateTime.now().year;
  return y != null && y >= 1900 && y <= now ? null : 'Enter a year from 1900 to $now, or leave it blank';
}

/// 12345 → 12,345.
String formatCount(int n) {
  final s = n.abs().toString();
  final b = StringBuffer(n < 0 ? '-' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}

/// [part] as a whole percentage of [whole], or null when there's no whole.
int? percent(int part, int whole) => whole == 0 ? null : (part * 100 / whole).round();
