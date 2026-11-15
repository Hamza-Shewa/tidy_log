import 'package:flutter/foundation.dart';
import 'package:tidy_log_core/tidy_log_core.dart';

import 'flutter_error_formatter.dart';

/// Prints one already-formatted line. Defaults to [debugPrint].
typedef LinePrinter = void Function(String line);

/// The app-facing logger.
///
/// Every line it prints starts with an ANSI reset when colours are on. The
/// `tidy_flutter` wrapper uses that marker to pass these lines through
/// untouched instead of restyling them a second time.
abstract final class TidyLog {
  static var _projectPackages = const <String>['app'];
  static var _minLevel = Level.debug;
  static var _enabled = kDebugMode;
  static var _color = true;
  static LinePrinter _printer = _defaultPrinter;
  static var _redactor = Redactor(TidyConfig.defaultRedactKeys);
  static FlutterErrorFormatter? _errorFormatter;

  /// Sets up the logger. Call it once, before [installErrorHooks].
  ///
  /// [projectPackages] lists your own packages; the first one is the app and
  /// its paths print as `lib/…`. Frames from these packages lead stack traces.
  static void configure({
    List<String>? projectPackages,
    Level? minLevel,
    bool? enabled,
    bool? color,
    List<String>? redactKeys,
    LinePrinter? printer,
  }) {
    if (projectPackages != null && projectPackages.isNotEmpty) _projectPackages = List.unmodifiable(projectPackages);
    if (minLevel != null) _minLevel = minLevel;
    if (enabled != null) _enabled = enabled;
    if (color != null) _color = color;
    if (redactKeys != null) _redactor = Redactor(redactKeys);
    if (printer != null) _printer = printer;
    _errorFormatter = null;
  }

  /// Restores the defaults. Meant for tests.
  @visibleForTesting
  static void reset() {
    _projectPackages = const ['app'];
    _minLevel = Level.debug;
    _enabled = kDebugMode;
    _color = true;
    _printer = _defaultPrinter;
    _redactor = Redactor(TidyConfig.defaultRedactKeys);
    _errorFormatter = null;
  }

  static List<String> get projectPackages => _projectPackages;

  static void v(Object? message, {String? tag, Object? error, StackTrace? stackTrace}) =>
      log(Level.verbose, message, tag: tag, error: error, stackTrace: stackTrace);
  static void d(Object? message, {String? tag, Object? error, StackTrace? stackTrace}) =>
      log(Level.debug, message, tag: tag, error: error, stackTrace: stackTrace);
  static void i(Object? message, {String? tag, Object? error, StackTrace? stackTrace}) =>
      log(Level.info, message, tag: tag, error: error, stackTrace: stackTrace);
  static void w(Object? message, {String? tag, Object? error, StackTrace? stackTrace}) =>
      log(Level.warning, message, tag: tag, error: error, stackTrace: stackTrace);
  static void e(Object? message, {String? tag, Object? error, StackTrace? stackTrace}) =>
      log(Level.error, message, tag: tag, error: error, stackTrace: stackTrace);

  static void log(Level level, Object? message, {String? tag, Object? error, StackTrace? stackTrace}) {
    if (!_enabled || level.index < _minLevel.index) return;
    emit(
      formatRecord(
        level: level,
        message: _redactor.apply('$message'),
        projectPackages: _projectPackages,
        tag: tag,
        error: error,
        stackTrace: stackTrace,
      ),
    );
  }

  /// Prints a prepared [Entry]. Used by the error hooks and the Dio
  /// interceptor; most code calls [log] instead.
  static void emit(Entry entry) {
    if (!_enabled) return;
    final renderer = Renderer(color: _color, includeSource: true);
    for (final line in renderer.render(entry)) {
      _printer(_color ? '\x1B[0m$line' : line);
    }
  }

  /// Applies the redaction keys to [text].
  static String redact(String text) => _redactor.apply(text);

  /// Replaces Flutter's error box with the tidy layout and logs uncaught
  /// async errors.
  ///
  /// Call it **before** setting up a crash reporter such as Sentry. Reporters
  /// keep the `FlutterError.onError` they find and call it after capturing,
  /// so they then call the tidy formatter instead of Flutter's error box.
  /// If another handler was set first, it is left alone and a one-line hint
  /// is printed, because replacing it would drop that reporter.
  ///
  /// The previous [PlatformDispatcher.onError] handler is kept and decides
  /// whether an uncaught async error counts as handled.
  ///
  /// In debug runs the widget inspector replaces [FlutterError.presentError]
  /// with its structured-error reporter as soon as the binding starts, and
  /// the Flutter tool then prints `Another exception was thrown: …` without
  /// a location for every error after the first. So the handler calls the
  /// tidy formatter directly. Pass [keepStructuredErrors] to route errors
  /// through `presentError` instead (IDE error links, DevTools' error list).
  static void installErrorHooks({bool keepStructuredErrors = false}) {
    // Read onError first: Dart initialises it lazily from presentError, so
    // reading it after the assignment below would return our own presenter.
    final current = FlutterError.onError;
    final defaultPresenter = FlutterError.presentError;
    void present(FlutterErrorDetails details) => (_errorFormatter ??= FlutterErrorFormatter()).present(details);
    FlutterError.presentError = present;
    if (current == null || current == FlutterError.dumpErrorToConsole || current == defaultPresenter) {
      FlutterError.onError = keepStructuredErrors ? (details) => FlutterError.presentError(details) : present;
    } else {
      emit(
        Entry(
          head: [
            Level.warning.labelSpan,
            const Span('FlutterError.onError was already set. Call TidyLog.installErrorHooks() before your crash reporter.', Tone.warning),
          ],
          source: 'tidy_log',
        ),
      );
    }

    final previous = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (error, stack) {
      log(Level.error, error, tag: 'uncaught', stackTrace: stack);
      return previous?.call(error, stack) ?? true;
    };
  }

  static void _defaultPrinter(String line) => debugPrint(line);
}
