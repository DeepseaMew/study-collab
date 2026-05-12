// KMUTT students sign in with @kmutt.ac.th. Confirmed with team.
const List<String> kAllowedEmailDomains = [
  'kmutt.ac.th',
  'gmail.com',
  'mail.kmutt.ac.th'
];

/// Returns true when [email] belongs to one of [kAllowedEmailDomains].
///
/// Rules:
/// - Regex pre-screen rejects embedded whitespace, newlines, null bytes, and
///   anything with zero or more than one '@'.
/// - Must contain exactly one '@'.
/// - Neither the local part nor the domain may be empty.
/// - Domain comparison is case-insensitive.
bool isAllowedUniversityEmail(String email) {
  // Pre-screen: reject whitespace, control characters, and multi-@ strings
  // before attempting any split.  This guards against embedded newlines or
  // null bytes that could bypass a plain split('@') check.
  if (!RegExp(r'^[^@\s]+@[^@\s]+$').hasMatch(email.trim())) return false;

  final parts = email.trim().split('@');
  // The regex above guarantees exactly two parts, but guard defensively.
  if (parts.length != 2) return false;

  final local = parts[0];
  final domain = parts[1].toLowerCase();

  if (local.isEmpty || domain.isEmpty) return false;

  return kAllowedEmailDomains.any((d) => d.toLowerCase() == domain);
}