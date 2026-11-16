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

/// One HTTP exchange, as the console shows it:
/// ```
/// POST /api/Auth/Signin  10.0.2.2:4013  ERR connection refused  74,991 ms · 15:21:09
///     body  {userId: 1, pin: ••••••••}
/// ```
/// The status is green for 2xx, cyan for 3xx, yellow for 4xx and red for
/// 5xx. An [outcome] (from a response rule) overrides that colour, and a
/// [verdict] is shown after the status: `200 ✕ unvalid api sign`. [rule]
/// says which rule decided, on its own detail line.
///
/// Used by the Dio box restyler and by the in-app Dio interceptor.
Entry httpEntry({
  required String method,
  required String url,
  int? status,
  String? error,
  int? durationMs,
  String? time,
  String? body,
  String? response,
  HttpOutcome? outcome,
  String? verdict,
  String? rule,
}) {
  final uri = Uri.tryParse(url);
  final hasHost = uri != null && uri.host.isNotEmpty;
  final path = !hasHost ? url : _decoded(uri.hasQuery ? '${uri.path}?${uri.query}' : uri.path);
  final host = !hasHost ? '' : '${uri.host}${uri.hasPort ? ':${uri.port}' : ''}';
  final meta = [if (durationMs != null) '${thousands(durationMs)} ms', ?time].join(' · ');
  final effective = outcome ?? httpOutcome(status: status, error: error);

  return Entry(
    head: [
      Span(method.toUpperCase(), Tone.accentBold),
      Span(' ${path.isEmpty ? '/' : path}'),
      if (host.isNotEmpty) Span('  $host', Tone.dim),
      const Span('  '),
      if (error != null) ...[
        const Span('ERR', Tone.errorBold),
        Span(' $error', Tone.error),
      ] else if (status != null)
        Span('$status', _statusTone(effective)),
      if (outcome != null && error == null) ?_marker(outcome, verdict),
      if (meta.isNotEmpty) Span('  $meta', Tone.dim),
    ],
    details: [
      if (rule != null) [const Span('rule  ', Tone.dim), Span(rule, Tone.secondary)],
      if (body != null && body.isNotEmpty) [const Span('body  ', Tone.dim), Span(cap(body))],
      if (response != null && response.isNotEmpty) [const Span('resp  ', Tone.dim), Span(cap(response))],
    ],
  );
}

Tone _statusTone(HttpOutcome outcome) => switch (outcome) {
  HttpOutcome.success => Tone.successBold,
  HttpOutcome.info => Tone.accentBold,
  HttpOutcome.warning => Tone.warning,
  HttpOutcome.error => Tone.errorBold,
};

/// `✕ reason` for errors, `! reason` for warnings, `· reason` otherwise.
///
/// Not `✗`: on Windows the Flutter tool rewrites `✗` to `X` in app output
/// when the terminal reports no emoji support (flutter_tools'
/// WindowsStdoutLogger).
Span? _marker(HttpOutcome outcome, String? verdict) {
  final text = verdict == null || verdict.isEmpty ? null : cap(verdict.replaceAll('\n', ' '), 80);
  return switch (outcome) {
    HttpOutcome.error => Span(text == null ? ' ✕' : ' ✕ $text', Tone.error),
    HttpOutcome.warning => Span(text == null ? ' !' : ' ! $text', Tone.warning),
    _ => text == null ? null : Span(' · $text', Tone.secondary),
  };
}

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
