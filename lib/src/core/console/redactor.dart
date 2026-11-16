/// Masks the values of sensitive keys in log text, for example
/// `{userId: 7, pin: 1234}` becomes `{userId: 7, pin: ••••••••}`.
///
/// Matches `key: value`, `key=value` and `"key":"value"`, case-insensitive,
/// only for the whole key (so `pin` does not touch `pinning`). JWTs are
/// masked wherever they appear, with or without a key.
final class Redactor {
  Redactor(List<String> keys)
    : _pattern = keys.isEmpty
          ? null
          : RegExp(
              '(?<![\\w-])(["\']?(?:${keys.map(RegExp.escape).join('|')})["\']?\\s*[:=]\\s*["\']?)((?:Bearer|Basic|Token)\\s+[^,}&"\'\\s|]+|[^,}&"\'\\s|]+)',
              caseSensitive: false,
            );

  static const mask = '••••••••';
  final RegExp? _pattern;

  /// A JWT (or any base64url JSON, which always starts with `eyJ`), masked
  /// wherever it appears: loggers sometimes print tokens without their key.
  static final _jwt = RegExp(r'eyJ[A-Za-z0-9_-]{10,}(?:\.[A-Za-z0-9_-]*)*');

  String apply(String text) {
    final masked = text.replaceAll(_jwt, mask);
    return _pattern == null ? masked : masked.replaceAllMapped(_pattern, (m) => '${m[1]}$mask');
  }
}
