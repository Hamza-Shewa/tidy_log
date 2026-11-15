import 'entry.dart';

const _esc = '\x1B[';
const _reset = '\x1B[0m';
final _ansiPattern = RegExp(r'\x1B\[[0-9;]*m');

/// The dim `· Tag` suffix this renderer writes, as found at the end of a
/// pre-rendered line (`ESC[90m<padding>· Tag  ×3ESC[0m`).
final _styledSuffix = RegExp(r'\x1B\[90m\s+·[^\x1B]*\x1B\[0m$');

/// Removes ANSI colour codes from [text].
String stripAnsi(String text) => text.replaceAll(_ansiPattern, '');

/// True when [text] starts with an ANSI escape, which marks lines that the
/// in-app logger has already styled.
bool startsWithAnsi(String text) => text.startsWith(_esc);

/// Turns [Entry] values into console lines.
///
/// [color] false gives plain text (used for the clean copy file and for
/// `NO_COLOR`). [maxHeadWidth] shortens very long head lines in the styled
/// view only; the plain copy always keeps the full text.
final class Renderer {
  const Renderer({this.color = true, bool? includeSource, this.maxHeadWidth, this.suffixColumn = 72})
    : includeSource = includeSource ?? color;

  final bool color;

  /// Whether the dim `· Tag` suffix is written. Off by default in plain mode,
  /// so the clean copy has no native tags.
  final bool includeSource;
  final int? maxHeadWidth;
  final int suffixColumn;

  static const _codes = <Tone, String>{
    Tone.dim: '90',
    Tone.secondary: '2',
    Tone.error: '31',
    Tone.errorBold: '1;31',
    Tone.warning: '33',
    Tone.accent: '36',
    Tone.accentBold: '1;36',
    Tone.success: '32',
    Tone.successBold: '1;32',
  };

  List<String> render(Entry entry) {
    if (entry.preRendered) {
      final text = entry.head.join();
      final line = color ? text : stripAnsi(includeSource ? text : text.replaceFirst(_styledSuffix, ''));
      return [if (entry.repeat > 1) '$line${_paint(' ×${entry.repeat}', Tone.dim)}' else line];
    }
    final head = _truncate(entry.head);
    final buffer = StringBuffer();
    for (final span in head) {
      buffer.write(_paint(span.text, span.tone));
    }
    final width = head.fold<int>(0, (sum, s) => sum + s.text.length);
    final tail = [
      if (includeSource && entry.source != null) '· ${entry.source}',
      if (entry.repeat > 1) '×${entry.repeat}',
    ].join('  ');
    if (tail.isNotEmpty) {
      final pad = includeSource && width < suffixColumn ? ' ' * (suffixColumn - width) : '  ';
      buffer.write(_paint('$pad$tail', Tone.dim));
    }
    return [
      buffer.toString().trimRight(),
      for (final detail in entry.details) '    ${detail.map((s) => _paint(s.text, s.tone)).join()}'.trimRight(),
      if (entry.similar > 0) _paint('    ↳ +${entry.similar} similar', Tone.dim),
    ];
  }

  List<Span> _truncate(List<Span> spans) {
    final max = maxHeadWidth;
    if (!color || max == null) return spans;
    var used = 0;
    final out = <Span>[];
    for (final span in spans) {
      if (used + span.text.length <= max) {
        out.add(span);
        used += span.text.length;
        continue;
      }
      final keep = max - used - 1;
      if (keep > 0) out.add(Span('${span.text.substring(0, keep)}…', span.tone));
      break;
    }
    return out;
  }

  String _paint(String text, Tone tone) {
    final code = _codes[tone];
    if (!color || code == null || text.isEmpty) return text;
    return '$_esc${code}m$text$_reset';
  }
}
