/// Masks the values of sensitive keys in log text, for example
/// `{userId: 7, walletPin: 1234}` becomes `{userId: 7, walletPin: ••••••••}`.
///
/// Matches `key: value`, `key=value`, `"key":"value"`, escaped JSON
/// (`\"key\":\"value\"`) and form keys (`user[password]=value`),
/// case-insensitive. A key is sensitive when it equals one of [keys] or ends
/// with it (`walletPin`, `smsOtp`, `softToken`, `refreshToken`,
/// `newPassword`), so `pin` does not touch `pinning` or `pinCount`, and
/// `token` does not touch `tokenExpiry`. JWTs are masked wherever they
/// appear, with or without a key.
///
/// The whole value is masked:
/// - a quoted value up to its closing quote (`"p@ss, word!"`);
/// - a `[…]` list or `{…}` map as a whole;
/// - after `:`, everything up to a `,`, `}`, `]` or `)` that closes nothing
///   inside the value, a ` | ` column separator or the end of the line, so
///   `password: correct horse battery` is masked in full;
/// - after `=` (queries, forms, cookies), up to a space, `&`, `;` or `,`;
/// - after `Bearer`, `Basic` or `Token`, the credential; after `Digest`, all
///   its parameters.
///
/// ANSI colour codes (`ESC[…m`) are skipped while matching and kept in the
/// output, outside the mask, so a coloured line keeps its colours and a key
/// right after a colour code is still found.
final class Redactor {
  Redactor(List<String> keys) : _keys = [for (final k in keys) _normalize(k)].where((k) => k.isNotEmpty).toList();

  final List<String> _keys;

  static const mask = '••••••••';

  /// A key and its separator. The value is not part of the match, so a key
  /// that is not sensitive never hides the next one (`state: token: abc`).
  /// Groups: 1 the key (with any `[…]` suffixes), 2 `:` or `=`, 3 the quote
  /// that opens the value, if any (`\"` in escaped JSON).
  static final _key = RegExp(
    r'''(?<![\w-])\\?["']?([A-Za-z][A-Za-z0-9_-]*(?:\[[A-Za-z0-9_-]*\])*)\\?["']?\s*([:=])\s*(\\?["']|)''',
  );

  /// An authorization scheme in front of the credential.
  static final _scheme = RegExp(r'(Bearer|Basic|Token|Digest)\s+', caseSensitive: false);

  /// A colour code (SGR), the only escape sequence loggers put in a line.
  static final _sgr = RegExp(r'\x1B\[[0-9;]*m');

  /// A JWT (or any base64url JSON, which always starts with `eyJ`), masked
  /// wherever it appears: loggers sometimes print tokens without their key.
  static final _jwt = RegExp(r'eyJ[A-Za-z0-9_-]{10,}(?:\.[A-Za-z0-9_-]*)*');

  static String _normalize(String key) => key.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');

  /// Whether [key] names a secret. For a form key (`user[password]`) the
  /// last named part decides.
  bool isSensitiveKey(String key) {
    final parts = key.split(RegExp(r'[\[\]]')).where((p) => p.isNotEmpty && int.tryParse(p) == null);
    if (parts.isEmpty) return false;
    final n = _normalize(parts.last);
    return n.isNotEmpty && _keys.any(n.endsWith);
  }

  String apply(String text) {
    if (text.isEmpty) return text;
    // Match on the text without colour codes; remember where each code was.
    final codes = <(int, String)>[];
    final plain = StringBuffer();
    var last = 0;
    for (final m in _sgr.allMatches(text)) {
      plain.write(text.substring(last, m.start));
      codes.add((plain.length, m[0]!));
      last = m.end;
    }
    plain.write(text.substring(last));
    final p = plain.toString();

    final ranges = <(int, int)>[];
    if (_keys.isNotEmpty) {
      var from = 0;
      for (final key in _key.allMatches(p)) {
        if (key.start < from || !isSensitiveKey(key[1]!)) continue;
        final start = key.end;
        final end = _valueEnd(p, start, equals: key[2] == '=', quote: key[3]!);
        if (end > start) {
          ranges.add((start, end));
          from = end;
        }
      }
    }
    for (final m in _jwt.allMatches(p)) {
      ranges.add((m.start, m.end));
    }
    if (ranges.isEmpty) return text;
    ranges.sort((a, b) => a.$1.compareTo(b.$1));

    final out = StringBuffer();
    var code = 0;
    var pos = 0;
    void copyTo(int end, {bool masked = false}) {
      // Colour codes inside a masked value are kept, after the mask.
      while (code < codes.length && codes[code].$1 <= end && (codes[code].$1 < end || !masked)) {
        if (!masked) out.write(p.substring(pos, codes[code].$1));
        out.write(codes[code].$2);
        if (!masked) pos = codes[code].$1;
        code++;
      }
      if (!masked) out.write(p.substring(pos, end));
      pos = end;
    }

    for (final (start, end) in ranges) {
      if (end <= pos) continue;
      if (start >= pos) {
        copyTo(start);
        out.write(mask);
      }
      // A range that overlaps the one before only extends its mask.
      copyTo(end, masked: true);
    }
    copyTo(p.length);
    return out.toString();
  }

  /// Where the value that starts at [start] ends (exclusive). Returns [start]
  /// when there is no value (`refreshToken: , …`, `authorization: | …`).
  static int _valueEnd(String p, int start, {required bool equals, required String quote}) {
    if (quote.isNotEmpty) return _quotedEnd(p, start, quote);
    var i = start;
    var digest = false;
    if (_scheme.matchAsPrefix(p, start) case final scheme?) {
      i = scheme.end;
      digest = scheme[1]!.toLowerCase() == 'digest';
    }
    var depth = 0;
    var quoted = false; // inside the "…" of a Digest parameter
    for (; i < p.length; i++) {
      final c = p[i];
      if (c == '\n' || c == '\r') break;
      if (digest && c == '"') quoted = !quoted;
      if (quoted) continue;
      if (c == '[' || c == '{' || c == '(') {
        depth++;
      } else if (c == ']' || c == '}' || c == ')') {
        if (depth == 0) break;
        depth--;
      } else if (depth == 0) {
        // ` | ` separates columns (`authorization: | content-type: …`).
        if (c == '|' && _isSpace(p, i - 1) && (i + 1 == p.length || _isSpace(p, i + 1))) break;
        if (digest) continue;
        if (c == ',') break;
        if (equals && (c == '&' || c == ';' || c == ' ' || c == '\t')) break;
      }
    }
    while (i > start && _isSpace(p, i - 1)) {
      i--;
    }
    return i;
  }

  /// The end of a quoted value: the closing [quote] that is not escaped, or
  /// the end of the line. In escaped JSON ([quote] is `\"`) the closing quote
  /// is `\"` and a quote inside the value is `\\\"`.
  static int _quotedEnd(String p, int start, String quote) {
    final escaped = quote.length == 2;
    final q = quote[quote.length - 1];
    for (var i = start; i < p.length; i++) {
      final c = p[i];
      if (c == '\n' || c == '\r') return i;
      if (c != q) continue;
      var slashes = 0;
      while (i - slashes - 1 >= start && p[i - slashes - 1] == r'\') {
        slashes++;
      }
      if (slashes.isEven) return i;
      if (escaped && slashes % 4 == 1) return i - 1;
    }
    return p.length;
  }

  static bool _isSpace(String p, int i) => i >= 0 && i < p.length && (p[i] == ' ' || p[i] == '\t');
}
