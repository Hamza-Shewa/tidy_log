import '../renderer.dart' show startsWithAnsi;
import 'logcat_line.dart';

/// The code TidyLog's in-app logger puts at the start of every coloured line
/// it prints (a reset, so the line starts from the default style).
const tidyLogLineMarker = '\x1B[0m';

/// True for a line TidyLog's in-app logger printed: it was redacted in the
/// app and is passed through as is. Other coloured lines (from `logger` and
/// similar packages) are also passed through, but redacted first.
bool isTidyLogLine(String text) => text.startsWith(tidyLogLineMarker);

/// Consecutive logcat lines that belong together: a header line plus its
/// continuation lines (stack frames, `Caused by:`, wrapped text, a Dio box).
final class Block {
  Block(this.first, {this.boxTail = false, DateTime? at})
    : messages = [first.message],
      last = first.message,
      lastAt = at;

  final LogcatLine first;
  final List<String> messages;

  /// The rest of an HTTP box whose start was already closed (it was split by
  /// a long pause). It is counted, never printed.
  final bool boxTail;

  /// The last line added, also when it was only counted.
  String last;

  /// When the last line arrived.
  DateTime? lastAt;

  /// Box lines past the line cap: counted, not kept.
  int dropped = 0;

  /// A line that was already styled, by the in-app logger or another logging
  /// package. It never takes continuation lines.
  bool get preRendered => first.isDart && startsWithAnsi(first.message);

  bool get isDioBox => messages.first.startsWith('┌');

  /// A box from a pretty_dio_logger style interceptor (`╔╣ Request ║ GET`).
  bool get isPrettyBox => messages.first.startsWith('╔╣');

  /// A pretty box, or the tail of one: it stays open while other sources
  /// print, and on an idle [BlockFolder.flush] until it looks finished.
  bool get isBox => isPrettyBox || boxTail;

  /// Number of lines this block stands for.
  int get lineCount => messages.length + dropped;
}

final _prettyLine = RegExp(r'^[╔║╟╚]');

final _continuation = RegExp(r'^(Caused by: |\.\.\. \d+ more|#\d+\s|<asynchronous suspension>|[│|├└])');
final _exception = RegExp(r'^([A-Za-z_$][\w$]*\.)+[A-Z][\w$]*(Exception|Error|Throwable)\b');

/// Groups logcat lines into [Block]s.
///
/// Lines stream in one at a time, so a block stays open until a line arrives
/// that cannot continue it, or until [flush] is called (the wrapper calls it
/// when the output goes quiet).
///
/// One block is open per source (tag, pid and level). A line from another
/// source closes an ordinary block, as before, but not a pretty_dio_logger
/// box: a native line printed in the middle of a box must not split it, or
/// the rest of the box (a wrapped token, say) would print raw. For the same
/// reason an idle [flush] keeps a box open until its last line is a `╚`
/// rule or no line arrived for [boxTimeout]; a box line that still arrives
/// after its box was closed is counted, never printed. Past [maxLines] a box
/// keeps its open state but only counts its lines ([Block.dropped]).
final class BlockFolder {
  BlockFolder({this.maxLines = 400, this.boxTimeout = const Duration(seconds: 2), DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final int maxLines;
  final Duration boxTimeout;
  final DateTime Function() _clock;

  /// Open blocks by source, oldest first.
  final _open = <String, Block>{};

  /// Sources that printed a pretty box: only there can a box tail turn up.
  final _boxSources = <String>{};

  /// Whether a box is held open, waiting for the rest of its lines. While it
  /// is, the caller should [flush] again after [boxTimeout].
  bool get holdsBox => _open.values.any((b) => b.isBox);

  /// Adds [line] and returns the blocks it closed.
  List<Block> add(LogcatLine line) {
    final source = _source(line);
    final closed = <Block>[
      for (final MapEntry<String, Block>(:key, :value) in [..._open.entries])
        if (key != source && !value.isBox) _open.remove(key)!,
    ];
    final now = _clock();
    final open = _open[source];
    if (open != null && _continues(open, line)) {
      open.lastAt = now;
      if (line.message.trim().isNotEmpty) open.last = line.message;
      if (open.isBox && open.messages.length >= maxLines) {
        open.dropped++;
        return closed;
      }
      open.messages.add(line.message);
      if ((open.isDioBox && line.message.startsWith('└')) || (!open.isBox && open.messages.length >= maxLines)) {
        closed.add(_open.remove(source)!);
      }
      return closed;
    }
    if (open != null) closed.add(_open.remove(source)!);
    final message = line.message;
    final tail = _boxSources.contains(source) && _prettyLine.hasMatch(message) && !message.startsWith('╔╣');
    final block = Block(line, boxTail: tail, at: now);
    if (block.isPrettyBox) _boxSources.add(source);
    if (block.preRendered) return [...closed, block];
    _open[source] = block;
    return closed;
  }

  /// Closes the open blocks, except a box that is still waiting for its
  /// last lines (see [BlockFolder]). With [force] (the end of the run) it
  /// closes everything.
  List<Block> flush({bool force = false}) {
    final now = _clock();
    final closed = <Block>[];
    for (final MapEntry<String, Block>(:key, :value) in [..._open.entries]) {
      final waiting =
          value.isBox &&
          !value.last.startsWith('╚') &&
          (value.lastAt == null || now.difference(value.lastAt!) < boxTimeout);
      if (force || !waiting) closed.add(_open.remove(key)!);
    }
    return closed;
  }

  static String _source(LogcatLine line) => '${line.tag}\u0000${line.pid}\u0000${line.level.name}';

  static bool _continues(Block open, LogcatLine line) {
    if (open.preRendered || !open.first.sameSource(line)) return false;
    final message = line.message;
    if (line.isDart && startsWithAnsi(message)) return false;
    if (open.isDioBox) return true;
    if (message.startsWith('╔╣')) return false; // the next pretty box
    if (open.isBox) return message.trim().isEmpty || _prettyLine.hasMatch(message);
    if (message.trim().isEmpty) return true;
    if (message.startsWith(' ') || message.startsWith('\t')) return true;
    if (message.startsWith('┌')) return false;
    if (_continuation.hasMatch(message)) return true;
    return open.messages.length == 1 && _exception.hasMatch(message);
  }
}
