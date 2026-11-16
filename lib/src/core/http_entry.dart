import 'dart:convert';

import 'entry.dart';

/// How an HTTP exchange went, as the app sees it. Usually follows the status
/// code (see [httpOutcome]); a response rule can say otherwise, for example
/// a 200 whose body has `success: false`.
enum HttpOutcome { success, info, warning, error }

/// The outcome the status code alone suggests: a transport [error] or 5xx is
/// an error, 4xx a warning, 3xx info, anything else success.
HttpOutcome httpOutcome({int? status, String? error}) => switch (status) {
  _ when error != null => HttpOutcome.error,
  final s? when s >= 500 => HttpOutcome.error,
  final s? when s >= 400 => HttpOutcome.warning,
  final s? when s >= 300 => HttpOutcome.info,
  _ => HttpOutcome.success,
};

/// One HTTP exchange, as the console shows it, in fixed columns:
/// ```
/// POST   /api/Auth/Signin                                200 ✕    52 ms  10:19:25  10.0.2.2:4013
///     ✕ unvalid api sign
///     rule  type = 2 → error
///     body  userName: 218900000000
///           pin: ••••••••
///     resp  content:
///             validTo: 2032-07-30T16:19:26Z
///           type: 2
/// ```
/// The status is green for 2xx, cyan for 3xx, yellow for 4xx and red for
/// 5xx. An [outcome] (from a response rule) overrides that colour and adds a
/// mark (`✕` error, `!` warning); the [verdict] goes on its own line, and so
/// does the [rule] that decided, unless the outcome is a plain success.
///
/// [body] and [response] are data (maps, lists, JSON text, other text),
/// shown one field per line. [bodyLines] and [responseLines] are already
/// laid out (for example from another logger's output). Every line, the
/// path included, goes through [redact].
///
/// Used by the Dio box restyler, the pretty_dio_logger pairer and the
/// in-app Dio interceptor.
Entry httpEntry({
  required String method,
  required String url,
  int? status,
  String? error,
  int? durationMs,
  String? time,
  Object? body,
  Object? response,
  List<String>? bodyLines,
  List<String>? responseLines,
  HttpOutcome? outcome,
  String? verdict,
  String? rule,
  String Function(String)? redact,
}) {
  final r = redact ?? _same;
  final uri = Uri.tryParse(url);
  final hasHost = uri != null && uri.host.isNotEmpty;
  final rawPath = !hasHost ? url : _decoded(uri.hasQuery ? '${uri.path}?${uri.query}' : uri.path);
  final path = r(rawPath.isEmpty ? '/' : rawPath);
  final host = !hasHost ? '' : '${uri.host}${uri.hasPort ? ':${uri.port}' : ''}';
  final effective = outcome ?? httpOutcome(status: status, error: error);
  final mark = error != null ? null : _mark(outcome);

  final reason = error ?? (verdict == null || verdict.isEmpty ? null : verdict);
  return Entry(
    head: [
      Span(method.toUpperCase().padRight(_methodWidth), Tone.accentBold),
      Span(path.length >= _pathWidth ? path : path.padRight(_pathWidth)),
      const Span('  '),
      if (error != null)
        const Span('ERR', Tone.errorBold)
      else if (status != null)
        Span('$status', _statusTone(effective))
      else
        const Span('   '),
      mark ?? const Span('  '),
      // Sources without timing (for example another logger's output) skip
      // the empty columns, so the host follows the status.
      if (durationMs != null || time != null)
        Span(
          durationMs == null ? ' ' * _durationWidth : '${thousands(durationMs)} ms'.padLeft(_durationWidth),
          Tone.dim,
        ),
      if (time != null)
        Span('  $time', Tone.dim)
      else if (durationMs != null && host.isNotEmpty)
        const Span('          '),
      if (host.isNotEmpty) Span('  $host', Tone.dim),
    ],
    details: [
      if (reason != null) _reasonLine(error != null ? HttpOutcome.error : effective, r(reason)),
      if (rule != null && (effective == HttpOutcome.warning || effective == HttpOutcome.error))
        [const Span('rule  ', Tone.dim), Span(r(rule), Tone.secondary)],
      ..._section('body', bodyLines ?? dataLines(body), r),
      ..._section('resp', responseLines ?? dataLines(response), r),
    ],
  );
}

const _methodWidth = 7;
const _pathWidth = 46;
const _durationWidth = 9;
const _maxBodyLines = 14;
const _maxLineWidth = 110;

String _same(String text) => text;

Tone _statusTone(HttpOutcome outcome) => switch (outcome) {
  HttpOutcome.success => Tone.successBold,
  HttpOutcome.info => Tone.accentBold,
  HttpOutcome.warning => Tone.warning,
  HttpOutcome.error => Tone.errorBold,
};

/// ` ✕` for errors, ` !` for warnings, from a response rule's outcome.
///
/// Not `✗`: on Windows the Flutter tool rewrites `✗` to `X` in app output
/// when the terminal reports no emoji support (flutter_tools'
/// WindowsStdoutLogger).
Span? _mark(HttpOutcome? outcome) => switch (outcome) {
  HttpOutcome.error => const Span(' ✕', Tone.error),
  HttpOutcome.warning => const Span(' !', Tone.warning),
  _ => null,
};

List<Span> _reasonLine(HttpOutcome outcome, String reason) {
  final text = cap(reason.replaceAll(RegExp(r'\s*\n\s*'), ' '), _maxLineWidth);
  return switch (outcome) {
    HttpOutcome.error => [Span('✕ $text', Tone.error)],
    HttpOutcome.warning => [Span('! $text', Tone.warning)],
    _ => [Span('· $text', Tone.secondary)],
  };
}

/// `body  first line` then the other lines aligned under it, at most
/// [_maxBodyLines], each at most [_maxLineWidth] characters.
List<List<Span>> _section(String label, List<String> lines, String Function(String) redact) {
  if (lines.isEmpty) return const [];
  final shown = lines.take(_maxBodyLines).toList();
  return [
    for (var i = 0; i < shown.length; i++)
      [Span(i == 0 ? '$label  ' : ' ' * (label.length + 2), Tone.dim), Span(cap(redact(shown[i]), _maxLineWidth))],
    if (lines.length > shown.length)
      [Span('${' ' * (label.length + 2)}… ${lines.length - shown.length} more lines', Tone.dim)],
  ];
}

/// Lays out data one field per line: maps as `key: value` with nested maps
/// indented, lists inline when short and as `- item` lines otherwise, JSON
/// text decoded, other text split into its lines. Empty data gives no lines.
List<String> dataLines(Object? data) {
  if (data == null) return const [];
  if (data is String) {
    final text = data.trim();
    if (text.isEmpty) return const [];
    if (text.startsWith('{') || text.startsWith('[')) {
      try {
        return dataLines(jsonDecode(text));
      } on FormatException {
        // Not JSON: show it as text.
      }
    }
    final fields = _dartMapFields(text);
    if (fields != null) return fields;
    return [
      for (final line in text.split('\n'))
        if (line.trim().isNotEmpty) line.trimRight(),
    ];
  }
  if (data is Map && data.isEmpty || data is List && data.isEmpty) return const [];
  final out = <String>[];
  _layout(data, '', out);
  return out;
}

/// `{a: 1, b: [x, y], c: {d: 2}}` (a Dart map's `toString`) as its top-level
/// `key: value` fields, or null when [text] does not look like one.
List<String>? _dartMapFields(String text) {
  if (!text.startsWith('{') || !text.endsWith('}') || text.length < 3) return null;
  final inner = text.substring(1, text.length - 1);
  final fields = <String>[];
  var depth = 0;
  var start = 0;
  for (var i = 0; i < inner.length; i++) {
    final c = inner[i];
    if (c == '{' || c == '[') depth++;
    if (c == '}' || c == ']') depth--;
    if (depth == 0 && inner.startsWith(', ', i)) {
      fields.add(inner.substring(start, i).trim());
      start = i + 2;
    }
  }
  fields.add(inner.substring(start).trim());
  final keyed = RegExp(r'^[^\s:{}\[\]]+: ');
  return fields.every(keyed.hasMatch) ? fields : null;
}

void _layout(Object? value, String indent, List<String> out) {
  if (value is Map) {
    value.forEach((key, child) => _field('$key', child, indent, out));
  } else if (value is List) {
    for (final item in value) {
      if (item is Map && item.isNotEmpty) {
        final itemLines = <String>[];
        _layout(item, '', itemLines);
        for (var i = 0; i < itemLines.length; i++) {
          out.add('$indent${i == 0 ? '- ' : '  '}${itemLines[i]}');
        }
      } else {
        out.add('$indent- ${_scalar(item)}');
      }
    }
  } else {
    out.add('$indent${_scalar(value)}');
  }
}

void _field(String key, Object? value, String indent, List<String> out) {
  if (value is Map && value.isNotEmpty) {
    out.add('$indent$key:');
    _layout(value, '$indent  ', out);
  } else if (value is List && value.isNotEmpty) {
    final inline = value.every((v) => v is! Map && v is! List) ? '[${value.map(_scalar).join(', ')}]' : null;
    if (inline != null && inline.length <= 80) {
      out.add('$indent$key: $inline');
    } else {
      out.add('$indent$key:');
      _layout(value, '$indent  ', out);
    }
  } else {
    out.add('$indent$key: ${_scalar(value)}');
  }
}

String _scalar(Object? value) => switch (value) {
  null => 'null',
  Map() when value.isEmpty => '{}',
  List() when value.isEmpty => '[]',
  String() when value.isEmpty => '""',
  String() => value.replaceAll(RegExp(r'\s*\n\s*'), ' '),
  _ => '$value',
};

/// Shortens [text] to [max] characters with a trailing `…`.
String cap(String text, [int max = 300]) => text.length <= max ? text : '${text.substring(0, max - 1)}…';

/// `74991` → `74,991`.
String thousands(int n) => n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');

/// Percent-decoded for reading (`%3Credacted%3E` → `<redacted>`); left as is
/// when it is not valid percent-encoding.
String _decoded(String text) {
  try {
    return Uri.decodeFull(text);
  } on ArgumentError {
    return text;
  }
}
