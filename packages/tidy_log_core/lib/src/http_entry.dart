import 'entry.dart';

/// One HTTP exchange, as the console shows it:
/// ```
/// POST /api/Auth/Signin  10.0.2.2:4013  ERR Connection refused  74,991 ms · 15:21:09
///     body  {userId: 1, pin: ••••••••}
/// ```
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
}) {
  final uri = Uri.tryParse(url);
  final hasHost = uri != null && uri.host.isNotEmpty;
  final path = !hasHost ? url : (uri.hasQuery ? '${uri.path}?${uri.query}' : uri.path);
  final host = !hasHost ? '' : '${uri.host}${uri.hasPort ? ':${uri.port}' : ''}';
  final meta = [if (durationMs != null) '${thousands(durationMs)} ms', ?time].join(' · ');

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
        Span('$status', switch (status) {
          < 300 => Tone.successBold,
          < 400 => Tone.accentBold,
          _ => Tone.warning,
        }),
      if (meta.isNotEmpty) Span('  $meta', Tone.dim),
    ],
    details: [
      if (body != null && body.isNotEmpty) [const Span('body  ', Tone.dim), Span(cap(body))],
      if (response != null && response.isNotEmpty) [const Span('resp  ', Tone.dim), Span(cap(response))],
    ],
  );
}

/// Shortens [text] to [max] characters with a trailing `…`.
String cap(String text, [int max = 300]) => text.length <= max ? text : '${text.substring(0, max - 1)}…';

/// `74991` → `74,991`.
String thousands(int n) => n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
