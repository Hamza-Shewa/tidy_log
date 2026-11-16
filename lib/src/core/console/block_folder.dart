import '../renderer.dart' show startsWithAnsi;
import 'logcat_line.dart';

/// Consecutive logcat lines that belong together: a header line plus its
/// continuation lines (stack frames, `Caused by:`, wrapped text, a Dio box).
final class Block {
  Block(this.first) : messages = [first.message];

  final LogcatLine first;
  final List<String> messages;

  /// A line that the in-app logger already styled. It never takes
  /// continuation lines.
  bool get preRendered => first.isDart && startsWithAnsi(first.message);

  bool get isDioBox => messages.first.startsWith('┌');

  /// A box from a pretty_dio_logger style interceptor (`╔╣ Request ║ GET`).
  bool get isPrettyBox => messages.first.startsWith('╔╣');
}

final _prettyLine = RegExp(r'^[╔║╟╚]');

final _continuation = RegExp(r'^(Caused by: |\.\.\. \d+ more|#\d+\s|<asynchronous suspension>|[│|├└])');
final _exception = RegExp(r'^([A-Za-z_$][\w$]*\.)+[A-Z][\w$]*(Exception|Error|Throwable)\b');

/// Groups logcat lines into [Block]s.
///
/// Lines stream in one at a time, so a block stays open until a line arrives
/// that cannot continue it, or until [flush] is called (the wrapper calls it
/// when the output goes quiet).
final class BlockFolder {
  BlockFolder({this.maxLines = 400});

  final int maxLines;
  Block? _open;

  /// Adds [line] and returns the blocks it closed.
  List<Block> add(LogcatLine line) {
    final open = _open;
    if (open != null && _continues(open, line)) {
      open.messages.add(line.message);
      if (open.isDioBox && line.message.startsWith('└')) {
        _open = null;
        return [open];
      }
      if (open.messages.length >= maxLines) {
        _open = null;
        return [open];
      }
      return const [];
    }
    _open = Block(line);
    if (_open!.preRendered) {
      final done = _open!;
      _open = null;
      return [?open, done];
    }
    return [?open];
  }

  /// Closes the open block, if any.
  List<Block> flush() {
    final open = _open;
    _open = null;
    return [?open];
  }

  static bool _continues(Block open, LogcatLine line) {
    if (open.preRendered || !open.first.sameSource(line)) return false;
    final message = line.message;
    if (line.isDart && startsWithAnsi(message)) return false;
    if (open.isDioBox) return true;
    if (message.startsWith('╔╣')) return false; // the next pretty box
    if (open.isPrettyBox) return message.trim().isEmpty || _prettyLine.hasMatch(message);
    if (message.trim().isEmpty) return true;
    if (message.startsWith(' ') || message.startsWith('\t')) return true;
    if (message.startsWith('┌')) return false;
    if (_continuation.hasMatch(message)) return true;
    return open.messages.length == 1 && _exception.hasMatch(message);
  }
}
