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
  const PrettyBox._({required this.kind, this.method, this.url, this.status, this.errorType, this.message, this.body});

  final PrettyKind kind;
  final String? method;

  /// Decoded, without a trailing `?`: the key that pairs a request with its
  /// response.
  final String? url;
  final int? status;

  /// `connectionError`, `receiveTimeout`, … for errors without a response.
  final String? errorType;
  final String? message;

  /// The request body (from its `Body` table) or the response body, on one
  /// line.
  final String? body;

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
          body: table != null ? '{${table.value.join(', ')}}' : _flatten(bodyLines),
        );
      case 'Response':
        return PrettyBox._(
          kind: PrettyKind.response,
          method: header.length > 1 ? header[1] : null,
          url: _normalizeUrl(second),
          status: status == null ? null : int.parse(status),
          body: _flatten(bodyLines),
        );
      case 'DioError' when status != null:
        return PrettyBox._(
          kind: PrettyKind.error,
          url: _normalizeUrl(second),
          status: int.parse(status),
          body: _flatten(bodyLines),
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

  static bool _isHeaderSection(String? section) =>
      section != null && (section == 'Headers' || section == 'Query Parameters' || section == 'Extras');

  static String? _normalizeUrl(String? url) {
    if (url == null || url.isEmpty) return null;
    var decoded = url;
    try {
      decoded = Uri.decodeFull(url);
    } on ArgumentError {
      // Keep it as printed.
    }
    return decoded.endsWith('?') ? decoded.substring(0, decoded.length - 1) : decoded;
  }

  /// Joins a pretty-printed body into one line. A string the logger wrapped
  /// over several lines (it splits long values at its width) is joined back
  /// without spaces, so it can be recognised and masked as a whole.
  static String? _flatten(List<String> lines) {
    final buffer = StringBuffer();
    var inString = false;
    for (final raw in lines) {
      final piece = raw.trim();
      if (piece.isEmpty) continue;
      if (buffer.isNotEmpty && !inString) buffer.write(' ');
      buffer.write(piece);
      if ('"'.allMatches(piece).length.isOdd) inString = !inString;
    }
    if (buffer.isEmpty) return null;
    return buffer
        .toString()
        .replaceAllMapped(RegExp(r'([\[{])\s+'), (m) => m[1]!)
        .replaceAllMapped(RegExp(r'\s+([\]}])'), (m) => m[1]!);
  }
}

enum PrettyKind { request, response, error }

/// Pairs request boxes with their response or error box, and turns each pair
/// into one HTTP entry. Requests are held until their answer arrives;
/// [finish] reports the ones that never got one.
final class PrettyHttpPairer {
  /// [redact] masks secrets in bodies before they are shortened for the
  /// console, so a long token cannot push the rest of a body out of view.
  PrettyHttpPairer({String Function(String)? redact}) : _redact = redact ?? _same;

  static String _same(String text) => text;
  final String Function(String) _redact;
  final _open = <String, List<PrettyBox>>{};

  List<Entry> add(PrettyBox box) {
    switch (box.kind) {
      case PrettyKind.request:
        (_open[box.url ?? ''] ??= []).add(box);
        return const [];
      case PrettyKind.response || PrettyKind.error when box.url != null:
        final request = _take(box.url!);
        return [
          httpEntry(
            method: request?.method ?? box.method ?? 'HTTP',
            url: box.url!,
            status: box.status,
            body: _maybe(request?.body),
            response: _maybe(box.body),
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
              body: _maybe(request.body),
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
        () {
          final entry = httpEntry(method: request.method ?? 'HTTP', url: request.url ?? '', body: _maybe(request.body));
          return Entry(head: [...entry.head, const Span('no response logged', Tone.dim)], details: entry.details);
        }(),
    ];
    _open.clear();
    return entries;
  }

  String? _maybe(String? text) => text == null ? null : _redact(text);

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
