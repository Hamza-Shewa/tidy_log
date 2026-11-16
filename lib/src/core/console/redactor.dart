/// Masks the values of sensitive keys in log text, for example
/// `{userId: 7, walletPin: 1234}` becomes `{userId: 7, walletPin: ••••••••}`.
///
/// Matches `key: value`, `key=value` and `"key":"value"`, case-insensitive.
/// A key is sensitive when it equals one of [keys] or ends with it
/// (`walletPin`, `smsOtp`, `softToken`, `refreshToken`, `newPassword`), so
/// `pin` does not touch `pinning` or `pinCount`, and `token` does not touch
/// `tokenExpiry`. JWTs are masked wherever they appear, with
/// or without a key.
final class Redactor {
  Redactor(List<String> keys) : _keys = [for (final k in keys) _normalize(k)].where((k) => k.isNotEmpty).toList();

  final List<String> _keys;

  /// A key and its separator. The value is not part of the match, so a key
  /// that is not sensitive never hides the next one (`state: token: abc`).
  static final _key = RegExp('(?<![\\w-])(["\']?)([A-Za-z][A-Za-z0-9_-]*)(["\']?\\s*[:=]\\s*["\']?)');

  static final _value = RegExp('(?:Bearer|Basic|Token)\\s+[^,}&"\'\\s|]+|[^,}&"\'\\s|]+', caseSensitive: false);

  static String _normalize(String key) => key.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');

  bool _sensitive(String key) {
    final n = _normalize(key);
    return _keys.any(n.endsWith);
  }

  static const mask = '••••••••';

  /// A JWT (or any base64url JSON, which always starts with `eyJ`), masked
  /// wherever it appears: loggers sometimes print tokens without their key.
  static final _jwt = RegExp(r'eyJ[A-Za-z0-9_-]{10,}(?:\.[A-Za-z0-9_-]*)*');

  String apply(String text) {
    final masked = text.replaceAll(_jwt, mask);
    if (_keys.isEmpty) return masked;
    final out = StringBuffer();
    var last = 0;
    for (final key in _key.allMatches(masked)) {
      if (key.start < last || !_sensitive(key[2]!)) continue;
      final value = _value.matchAsPrefix(masked, key.end);
      if (value == null) continue;
      out
        ..write(masked.substring(last, key.end))
        ..write(mask);
      last = value.end;
    }
    return (out..write(masked.substring(last))).toString();
  }
}
