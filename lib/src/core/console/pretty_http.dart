import '../body_rule.dart';
import '../entry.dart';
import '../http_entry.dart';
import '../level.dart';

/// One box printed by a pretty_dio_logger style interceptor (for example
/// `PrettyDioLogger`, or a copy of it such as core_banking's
/// `CoreNetworkLogger`):
///
/// ```
/// ╔╣ Request ║ POST
/// ║  http://host/api/Auth/Signin?
/// ╚══════╝
/// ╔ Body
/// ╟ userName: 218900000000
/// ╚══════╝
/// ```
///
/// Responses start with `╔╣ Response ║ GET ║ Status: 200 OK`, errors with
/// `╔╣ DioError ║ Status: 401 Unauthorized` (URL, no method) or
/// `╔╣ DioError ║ DioExceptionType.connectionError` (a message, no URL).
final class PrettyBox {
  const PrettyBox._({
    required this.kind,
    this.method,
    this.url,
    this.status,
    this.errorType,
    this.message,
    this.body = const [],
  });

  final PrettyKind kind;
  final String? method;

  /// As printed, without a trailing `?`: the key that pairs a request with
  /// its response. It is not percent-decoded here: [httpEntry] masks the
  /// query on the raw text and decodes it once, for display.
  final String? url;
  final int? status;

  /// `connectionError`, `receiveTimeout`, … for errors without a response.
  final String? errorType;
  final String? message;

  /// The request body (from its `Body` table) or the response body, one
  /// field per line.
  final List<String> body;

  /// Parses the lines of one box (logcat prefix already removed). Returns
  /// null when [lines] is not such a box.
  static PrettyBox? parse(List<String> lines) {
    if (lines.isEmpty || !lines.first.startsWith('╔╣')) return null;
    final header = lines.first.substring(2).split('║').map((p) => p.trim()).toList();
    final second = lines.length > 1 && lines[1].startsWith('║') ? lines[1].substring(1).trim() : null;

    final tables = <String, List<String>>{};
    final bodyLines = <String>[];
    String? section;
    for (final line in lines.skip(2)) {
      if (line.startsWith('╔')) {
        section = line.substring(1).trim();
      } else if (line.startsWith('╚')) {
        section = null;
      } else if (line.startsWith('╟')) {
        (tables[section ?? ''] ??= []).add(line.substring(1).trim());
      } else if (line.startsWith('║') && !_isHeaderSection(section)) {
        bodyLines.add(line.substring(1));
      }
    }

    final status = header.length > 1 ? (RegExp(r'Status: (\d+)').firstMatch(header.last)?[1]) : null;
    switch (header.first) {
      case 'Request':
        final table = tables.entries.where((e) => e.key == 'Body' || e.key.startsWith('Form data')).firstOrNull;
        return PrettyBox._(
          kind: PrettyKind.request,
          method: header.length > 1 ? header[1] : null,
          url: _normalizeUrl(second),
          body: table != null ? table.value : _lines(bodyLines),
        );
      case 'Response':
        return PrettyBox._(
          kind: PrettyKind.response,
          method: header.length > 1 ? header[1] : null,
          url: _normalizeUrl(second),
          status: status == null ? null : int.parse(status),
          body: _lines(bodyLines),
        );
      case 'DioError' when status != null:
        return PrettyBox._(
          kind: PrettyKind.error,
          url: _normalizeUrl(second),
          status: int.parse(status),
          body: _lines(bodyLines),
        );
      case 'DioError':
        return PrettyBox._(
          kind: PrettyKind.error,
          errorType: header.length > 1 ? header[1].replaceFirst('DioExceptionType.', '') : null,
          message: second,
        );
      default:
        return null;
    }
  }

  /// `key: "value"` → `key: value`, like the in-app interceptor prints it.
  /// An empty string stays `""` so it is visibly empty.
  static String _unquote(String line) =>
      line.replaceFirstMapped(RegExp(r'^([^"]*?: )"(.+)"$'), (m) => '${m[1]}${m[2]}');

  static bool _isHeaderSection(String? section) =>
      section != null && (section == 'Headers' || section == 'Query Parameters' || section == 'Extras');

  static String? _normalizeUrl(String? url) {
    if (url == null || url.isEmpty) return null;
    return url.endsWith('?') ? url.substring(0, url.length - 1) : url;
  }

  /// The body as the logger printed it, one field per line: box characters,
  /// braces and trailing commas removed, nesting kept as two-space indents.
  /// A string the logger wrapped over several lines (it splits long values at
  /// its width) is joined back first, so it can be recognised and masked.
  static List<String> _lines(List<String> raw) {
    final joined = <String>[];
    var inString = false;
    for (final line in raw) {
      if (line.trim().isEmpty) continue;
      if (inString && joined.isNotEmpty) {
        joined[joined.length - 1] += line.trim();
      } else {
        joined.add(line.trimRight());
      }
      if ('"'.allMatches(line).length.isOdd) inString = !inString;
    }
    final brace = RegExp(r'^\s*[\[\]{}],?$');
    final kept = [
      for (final line in joined)
        if (!brace.hasMatch(line)) line,
    ];
    if (kept.isEmpty) return const [];
    int indentOf(String l) => l.length - l.trimLeft().length;
    final base = kept.map(indentOf).reduce((a, b) => a < b ? a : b);
    final out = <String>[];
    var itemStart = false;
    for (final line in joined) {
      if (brace.hasMatch(line)) {
        // A `{` deeper than the fields opens a list item: mark its first field.
        if (line.trim().startsWith('{') && indentOf(line) > base) itemStart = true;
        continue;
      }
      final level = (indentOf(line) - base) ~/ 4;
      final text = _unquote(line.trim().replaceFirst(RegExp(r',$'), '').replaceFirst(RegExp(r':\s*[\[{]$'), ':'));
      out.add(itemStart && level > 0 ? '${'  ' * (level - 1)}- $text' : '${'  ' * level}$text');
      itemStart = false;
    }
    return out;
  }
}

enum PrettyKind { request, response, error }

/// Pairs request boxes with their response or error box, and turns each pair
/// into one HTTP entry. Requests are held until their answer arrives;
/// [finish] reports the ones that never got one.
final class PrettyHttpPairer {
  /// [redact] masks secrets in bodies before they are shortened for the
  /// console, so a long token cannot push the rest of a body out of view.
  /// [rules] judge each response by its body (`http_rules` in
  /// `tidy_log.yaml`); the first verdict wins.
  PrettyHttpPairer({String Function(String)? redact, this.rules = const []}) : _redact = redact ?? _same;

  static String _same(String text) => text;
  final String Function(String) _redact;
  final List<FieldRule> rules;
  final _open = <String, List<PrettyBox>>{};

  List<Entry> add(PrettyBox box) {
    switch (box.kind) {
      case PrettyKind.request:
        (_open[box.url ?? ''] ??= []).add(box);
        return const [];
      case PrettyKind.response || PrettyKind.error when box.url != null:
        final request = _take(box.url!);
        final verdict = _judge(box.body);
        return [
          httpEntry(
            method: request?.method ?? box.method ?? 'HTTP',
            url: box.url!,
            status: box.status,
            outcome: verdict?.outcome,
            verdict: verdict?.message,
            rule: verdict?.rule,
            bodyLines: request?.body ?? const [],
            responseLines: box.body,
            redact: _redact,
          ),
        ];
      case _:
        // A transport error names no URL: it belongs to the only open
        // request, if there is exactly one.
        final error = _describe(box);
        final pending = _open.values.expand((q) => q).toList();
        if (pending.length == 1) {
          final request = _take(pending.single.url ?? '')!;
          return [
            httpEntry(
              method: request.method ?? 'HTTP',
              url: request.url ?? '',
              error: error,
              bodyLines: request.body,
              redact: _redact,
            ),
          ];
        }
        return [
          Entry(head: [Level.error.labelSpan, Span('HTTP $error', Tone.error)]),
        ];
    }
  }

  /// Requests that never got an answer, for the end of the run.
  List<Entry> finish() {
    final entries = [
      for (final request in _open.values.expand((q) => q))
        httpEntry(
          method: request.method ?? 'HTTP',
          url: request.url ?? '',
          verdict: 'no response logged',
          bodyLines: request.body,
          redact: _redact,
        ),
    ];
    _open.clear();
    return entries;
  }

  FieldVerdict? _judge(List<String> body) {
    if (rules.isEmpty || body.isEmpty) return null;
    final parsed = bodyFromLines(body);
    for (final rule in rules) {
      if (rule.decide(parsed) case final verdict?) return verdict;
    }
    return null;
  }

  PrettyBox? _take(String url) {
    final queue = _open[url];
    if (queue == null || queue.isEmpty) return null;
    final first = queue.removeAt(0);
    if (queue.isEmpty) _open.remove(url);
    return first;
  }

  /// `connectionError` + `The connection errored: Connection refused This
  /// indicates …` → `connection error: Connection refused`.
  static String _describe(PrettyBox box) {
    final type = (box.errorType ?? 'error').replaceAllMapped(RegExp('[A-Z]'), (m) => ' ${m[0]!.toLowerCase()}');
    var message = (box.message ?? '').split(' This indicates').first;
    message = message.replaceFirst(RegExp(r'^The connection errored:\s*'), '').trim();
    return message.isEmpty || message == 'null' ? type : '$type: $message';
  }
}
