/// Masks the values of sensitive keys in log text, for example
/// `{userId: 7, pin: 1234}` becomes `{userId: 7, pin: ••••••••}`.
///
/// Matches `key: value`, `key=value` and `"key":"value"`, case-insensitive,
/// only for the whole key (so `pin` does not touch `pinning`).
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

  String apply(String text) => _pattern == null ? text : text.replaceAllMapped(_pattern, (m) => '${m[1]}$mask');
}
