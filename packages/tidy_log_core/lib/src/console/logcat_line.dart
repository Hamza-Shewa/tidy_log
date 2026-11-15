import '../level.dart';

final _pattern = RegExp(r'^([VDIWEFA])\/(.+?)\s*\(\s*(\d+)\): ?(.*)$');

/// One Android logcat line as the Flutter tool prints it:
/// `E/FlutterSecureStorage(31800): message`.
final class LogcatLine {
  const LogcatLine({required this.level, required this.tag, required this.pid, required this.message});

  final Level level;
  final String tag;
  final int pid;
  final String message;

  /// Lines printed by Dart code (`print`, `debugPrint`).
  bool get isDart => tag == 'flutter';

  /// Same tag, pid and level, so the two lines can belong to one block.
  bool sameSource(LogcatLine other) => tag == other.tag && pid == other.pid && level == other.level;

  /// Returns null when [line] is not a logcat line (tool output, blank line).
  static LogcatLine? tryParse(String line) {
    final m = _pattern.firstMatch(line);
    if (m == null) return null;
    return LogcatLine(
      level: Level.fromLogcat(m[1]!),
      tag: m[2]!,
      pid: int.parse(m[3]!),
      message: m[4]!,
    );
  }
}
