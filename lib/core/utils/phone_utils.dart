/// Phone number normalization utilities for WhatsApp wa.me URLs.
///
/// Pakistani numbers are commonly stored in three formats:
///   - "03001234567" (local with leading 0)
///   - "923001234567" (international without +)
///   - "+923001234567" (international with +)
///
/// `wa.me/<number>` requires the digits-only international form
/// without the + (e.g. "923001234567").
class PhoneUtils {
  /// Returns the phone number in a wa.me-compatible format
  /// (digits-only, with Pakistani country code 92 if needed).
  /// Returns null if the input doesn't look like a valid number.
  static String? toWhatsAppFormat(String raw) {
    if (raw.isEmpty) return null;

    // Strip all non-digit characters (including +, spaces, dashes)
    var digits = raw.replaceAll(RegExp(r'[^\d]'), '');
    if (digits.isEmpty) return null;

    // "0092..." is the usual way to write an international dial-out locally.
    // Without this the leading-zero rule below turned it into "92092...".
    if (digits.startsWith('00')) digits = digits.substring(2);

    // Local format: 03XXXXXXXXX → 92 + 3XXXXXXXXX
    if (digits.startsWith('0') && digits.length >= 10) {
      return '92${digits.substring(1)}';
    }

    // Already international (with country code)
    if (digits.startsWith('92') && digits.length >= 11) {
      return digits;
    }

    // Bare local number without leading 0 (less common)
    if (digits.length == 10 && digits.startsWith('3')) {
      return '92$digits';
    }

    // Unrecognized format — return digits as-is for best-effort
    return digits;
  }
}
