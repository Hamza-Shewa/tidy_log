import 'package:flutter/foundation.dart';
import 'package:tidy_log/tidy_log.dart';

/// What the scenarios log through. The composition root in `main.dart` picks
/// the implementation, so the same scenario can be compared with and
/// without tidy_log.
abstract interface class AppLogger {
  void d(String message, {String? tag});
  void i(String message, {String? tag});
  void w(String message, {String? tag});
  void e(String message, {String? tag, Object? error, StackTrace? stackTrace});
}

/// Logs through [TidyLog]: styled lines, trimmed stacks, masked secrets.
final class TidyAppLogger implements AppLogger {
  const TidyAppLogger();

  @override
  void d(String message, {String? tag}) => TidyLog.d(message, tag: tag);
  @override
  void i(String message, {String? tag}) => TidyLog.i(message, tag: tag);
  @override
  void w(String message, {String? tag}) => TidyLog.w(message, tag: tag);
  @override
  void e(String message, {String? tag, Object? error, StackTrace? stackTrace}) =>
      TidyLog.e(message, tag: tag, error: error, stackTrace: stackTrace);
}

/// What an app without tidy_log typically does: `debugPrint` the message,
/// then the error and the full stack trace. Nothing is masked.
final class PlainAppLogger implements AppLogger {
  const PlainAppLogger({this._printer});

  final DebugPrintCallback? _printer;

  /// Defaults to [debugPrint]; tests pass their own.
  DebugPrintCallback get printer => _printer ?? debugPrint;

  @override
  void d(String message, {String? tag}) => _print('D', message, tag);
  @override
  void i(String message, {String? tag}) => _print('I', message, tag);
  @override
  void w(String message, {String? tag}) => _print('W', message, tag);
  @override
  void e(String message, {String? tag, Object? error, StackTrace? stackTrace}) {
    _print('E', message, tag);
    if (error != null) printer('$error');
    if (stackTrace != null) printer('$stackTrace');
  }

  void _print(String level, String message, String? tag) => printer(tag == null ? '$level $message' : '$level [$tag] $message');
}
