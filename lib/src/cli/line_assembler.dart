import 'dart:async';

/// Splits decoded text into lines, as `LineSplitter` does (`\n`, `\r\n` or a
/// lone `\r` end a line), without holding back a line that is still being
/// written.
///
/// The Flutter tool prints progress text first and its newline only when the
/// step ends (`Running Gradle task 'assembleDebug'...` then, much later,
/// `  12.3s`), and asks for a device with a prompt that has no newline at
/// all. Once such a partial line has waited [delay], [onPartial] gets it, so
/// it shows while flutter works or waits for a key. When the line is done,
/// [onLine] gets all of it together with how much of it was already shown.
final class LineAssembler {
  LineAssembler({required this.onLine, required this.onPartial, this.delay = const Duration(milliseconds: 100)});

  /// A complete line, without its line break. Its first [shown] characters
  /// already went out through [onPartial]; 0 means none did.
  final void Function(String line, int shown) onLine;

  /// The part of the pending line that has not been shown yet.
  final void Function(String text) onPartial;

  final Duration delay;

  String _pending = '';
  int _shown = 0;
  bool _afterCr = false;
  Timer? _timer;

  void add(String chunk) {
    var start = 0;
    if (_afterCr && chunk.startsWith('\n')) start = 1; // the \n of a \r\n split across chunks
    _afterCr = false;
    for (var i = start; i < chunk.length; i++) {
      final c = chunk.codeUnitAt(i);
      if (c != 0x0A && c != 0x0D) continue;
      _emit(_pending + chunk.substring(start, i));
      if (c == 0x0D) {
        if (i + 1 == chunk.length) {
          _afterCr = true;
        } else if (chunk.codeUnitAt(i + 1) == 0x0A) {
          i++;
        }
      }
      start = i + 1;
    }
    _pending += chunk.substring(start);
    if (_pending.length > _shown) _timer ??= Timer(delay, _showPartial);
  }

  /// The end of the input: a last line without a line break is still a line.
  void close() {
    if (_pending.isNotEmpty) _emit(_pending);
    _timer?.cancel();
    _timer = null;
  }

  void _emit(String line) {
    _timer?.cancel();
    _timer = null;
    final shown = _shown;
    _pending = '';
    _shown = 0;
    onLine(line, shown);
  }

  void _showPartial() {
    _timer = null;
    if (_pending.length <= _shown) return;
    final text = _pending.substring(_shown);
    _shown = _pending.length;
    onPartial(text);
  }
}
