/// The visual role of a piece of text. The renderer maps tones to ANSI styles
/// (or drops them in plain mode), so formatting logic never deals with escape
/// codes directly.
enum Tone {
  plain,
  dim,
  secondary,
  error,
  errorBold,
  warning,
  accent,
  accentBold,
  success,
  successBold,

  /// A source location (`lib/a.dart:12:3`, `Main.kt:40`).
  path,

  /// A source location in a dimmed trail.
  pathDim,
}

/// A run of text with one tone.
final class Span {
  const Span(this.text, [this.tone = Tone.plain]);

  final String text;
  final Tone tone;

  @override
  String toString() => text;
}

/// One rendered log item: a head line plus indented detail lines.
///
/// [key] identifies exact repeats, [similarKey] near-duplicates (same source
/// and template). Both are compared by the repeat collapser.
final class Entry {
  Entry({
    required this.head,
    this.source,
    this.details = const [],
    String? key,
    this.similarKey,
    this.preRendered = false,
  }) : key = key ?? _plainKey(head, source, details);

  /// Divider line such as `──── app started · pid 31800 ────`.
  factory Entry.divider(String label) => Entry(head: [Span('──────── $label ────────', Tone.dim)]);

  /// A line that was already styled (for example by the in-app logger) and is
  /// passed through as is.
  factory Entry.raw(String line) => Entry(head: [Span(line)], preRendered: true, key: line);

  final List<Span> head;

  /// Native tag (and pid when it differs from the current process), shown as
  /// a dim suffix.
  final String? source;
  final List<List<Span>> details;
  final String key;
  final String? similarKey;
  final bool preRendered;

  /// How many identical entries this one stands for.
  int repeat = 1;

  /// How many near-duplicate entries were folded into this one.
  int similar = 0;

  static String _plainKey(List<Span> head, String? source, List<List<Span>> details) =>
      [head.join(), source ?? '', for (final d in details) d.join()].join('\u0000');
}
