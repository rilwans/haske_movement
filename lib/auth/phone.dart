/// Turns a phone number as a canvasser types it into E.164, the form Erims
/// stores: 0803 123 4567, 803 123 4567, 2348031234567 and +2348031234567
/// all become +2348031234567. Returns null when it can't be a phone number.
String? toE164(String input) {
  var digits = input.replaceAll(RegExp(r'[\s\-().]'), '');
  if (digits.startsWith('+')) {
    // Already international.
  } else if (digits.startsWith('234')) {
    digits = '+$digits';
  } else if (digits.startsWith('0') && digits.length == 11) {
    digits = '+234${digits.substring(1)}';
  } else if (digits.length == 10) {
    digits = '+234$digits';
  }
  return RegExp(r'^\+[1-9][0-9]{7,14}$').hasMatch(digits) ? digits : null;
}
