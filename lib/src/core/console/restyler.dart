import '../entry.dart';
import '../http_entry.dart';
import '../java_stack.dart';
import '../level.dart';
import '../record_formatter.dart';
import '../stack_trimmer.dart';
import 'block_folder.dart';
import 'config.dart';

final _dartFrame = RegExp(r'^#\d+\s');
final _javaFrame = RegExp(r'^\s*at (.+)$');
final _nav = RegExp(r'^from (\S+) (Pushed|Popped|Replaced|Removed) route: (\S+)$');
final _engine = RegExp(r'^\[(IMPORTANT|ERROR|WARNING|INFO|VERBOSE):[^\]]*\]\s*(.*)$');
final _errorWords = RegExp(r'error|exception|fail', caseSensitive: false);

/// The blank label used for plain Dart lines, so messages line up with `ERR `.
const blankLabel = Span('    ');

/// Turns one [Block] of logcat lines into an [Entry].
final class Restyler {
  Restyler(this.config);

  final TidyConfig config;

  Entry restyle(Block block, {required int? currentPid}) {
    final first = block.first;
    final source = [
      if (!first.isDart) first.tag,
      if (currentPid != null && first.pid != currentPid) 'pid ${first.pid}',
    ].join(' · ');
    final src = source.isEmpty ? null : source;

    if (block.preRendered) return Entry.raw(first.message);
    if (block.isDioBox) return _dio(block.messages) ?? _plain(block, src);
    if (block.messages.any(_dartFrame.hasMatch)) return _dartTrace(block, src);
    if (block.messages.skip(1).any(_javaFrame.hasMatch)) return _javaTrace(block, src);
    if (block.messages.length > 1) return _plain(block, src);
    return _single(block, src);
  }

  Entry _single(Block block, String? source) {
    final first = block.first;
    final message = first.message;
    if (first.isDart) {
      final nav = _nav.firstMatch(message);
      if (nav != null) return _navEntry(nav[1]!, nav[2]!, nav[3]!, source);
      final engine = _engine.firstMatch(message);
      if (engine != null) {
        final level = switch (engine[1]) {
          'ERROR' => Level.error,
          'WARNING' => Level.warning,
          'VERBOSE' => Level.verbose,
          _ => Level.info,
        };
        return Entry(head: [level.labelSpan, Span(engine[2]!, level.messageTone)], source: 'engine');
      }
      for (final rule in config.rules) {
        if (rule.pattern.hasMatch(message)) {
          return Entry(head: [Span('${rule.label} ', rule.tone), Span(message)], source: source);
        }
      }
      return Entry(head: [blankLabel, Span(message)], source: source);
    }
    final level = first.level;
    return Entry(
      head: [level.labelSpan, Span(message, level.messageTone)],
      source: source,
      similarKey: message.length >= 32 ? '${first.tag}|${level.name}|${message.substring(0, 32)}' : null,
    );
  }

  Entry _plain(Block block, String? source) {
    final first = block.first;
    final label = first.isDart ? blankLabel : first.level.labelSpan;
    final tone = first.isDart ? Tone.plain : first.level.messageTone;
    return Entry(
      head: [label, Span(block.messages.first, tone)],
      source: source,
      details: [
        for (final line in block.messages.skip(1))
          if (line.trim().isNotEmpty) [Span(line.trim(), Tone.secondary)],
      ],
    );
  }

  Entry _navEntry(String from, String verb, String to, String? source) {
    final (a, b, word) = switch (verb) {
      'Pushed' => (from, to, null),
      'Popped' => (to, from, 'back'),
      'Replaced' => (from, to, 'replace'),
      _ => (to, from, 'remove'),
    };
    return Entry(
      head: [
        const Span('NAV ', Tone.accentBold),
        if (word != null) Span('$word ', Tone.dim),
        Span(a),
        const Span(' → ', Tone.accent),
        Span(b),
      ],
      source: source,
    );
  }

  Entry _dartTrace(Block block, String? source) {
    final start = block.messages.indexWhere(_dartFrame.hasMatch);
    final header = [
      for (final l in block.messages.take(start))
        if (l.trim().isNotEmpty) l.trim(),
    ];
    final title = header.isEmpty ? 'Stack trace' : header.first;
    final level = _errorWords.hasMatch(title) ? Level.error : Level.warning;
    final stack = trimStackText(
      block.messages.skip(start).map((l) => l.trim()).join('\n'),
      projectPackages: config.projectPackages,
    );
    return Entry(
      head: [level.labelSpan, Span(title, Tone.errorBold)],
      source: source,
      details: [
        for (final line in header.skip(1)) [Span(line, level.messageTone)],
        ...stackDetails(stack, level),
      ],
    );
  }

  Entry _javaTrace(Block block, String? source) {
    final level = block.first.level;
    final header = block.messages.first.trim();
    final stack = parseJavaStack(block.messages)!;
    // The header is often a message ("Failed to handle method call") with
    // the exception on the next line.
    final exception = isJavaException(header) ? null : stack.exception;
    final note = stack.note;
    return Entry(
      head: [level.labelSpan, Span(header, level.messageTone)],
      source: source,
      details: [
        if (exception != null) [Span(exception, level.messageTone)],
        [Span('at ${stack.frame}', level.messageTone)],
        if (note.isNotEmpty) [Span('┊ $note', Tone.dim)],
      ],
    );
  }

  Entry? _dio(List<String> lines) {
    final body = <String>[];
    String? method, url, time, duration, response, code, error;
    var inHeaders = false;
    for (final raw in lines) {
      final line = raw.replaceFirst(RegExp(r'^[┌│|├└]-*\s?'), '').trim();
      if (line.isEmpty) continue;
      final request = RegExp(r'^\[DIO\] Request: (\S+) (\S+)').firstMatch(line);
      final resp = RegExp(r'^\[DIO\] Response \[code (\d+)\]: ?(.*)$').firstMatch(line);
      if (request != null) {
        (method, url) = (request[1], request[2]);
      } else if (line.startsWith('Time: ')) {
        time = RegExp(r'(\d{2}:\d{2}:\d{2})').firstMatch(line)?[1];
      } else if (line == 'Headers:') {
        inHeaders = true;
      } else if (resp != null) {
        (code, response) = (resp[1], resp[2]);
      } else if (line.startsWith('[DIO] Error: ')) {
        error = line.substring('[DIO] Error: '.length);
      } else if (line.startsWith('[DIO] Duration: ')) {
        duration = RegExp(r'(\d+)').firstMatch(line)?[1];
      } else if (inHeaders) {
        inHeaders = false;
      } else if (method != null && response == null && error == null) {
        body.add(line);
      }
    }
    if (method == null || url == null) return null;
    return httpEntry(
      method: method,
      url: url,
      status: code == null ? null : int.tryParse(code),
      error: error == null ? null : _shortDioError(error),
      durationMs: duration == null ? null : int.parse(duration),
      time: time,
      body: body.join(' '),
      response: response,
    );
  }

  static String _shortDioError(String error) {
    var text = error.split(' (OS Error').first;
    if (text.endsWith(':')) text = text.substring(0, text.length - 1);
    text = text.replaceFirst(RegExp(r':\s*null$'), '').trim();
    return text.isEmpty || text == 'null' ? 'no response' : text;
  }
}
