import 'package:flutter/foundation.dart';
import '../core.dart';

import 'error_text.dart';
import 'flutter_error_formatter.dart';
import 'http_rules.dart';

/// Prints one already-formatted line. Defaults to [debugPrint].
typedef LinePrinter = void Function(String line);

var _reportingFailure = false;

/// Runs [body], the logging work behind one public call, and reports whether
/// it finished. Logging never throws into the app: if [body] throws (a
/// `toString()` or `printer` that throws, a broken hook, a malformed URL), one
/// plain `tidy_log: could not log (<type>)` line goes to [debugPrint] instead.
/// That line is skipped while it is being printed, so a `debugPrint` that
/// logs through [TidyLog] cannot loop. Not exported.
bool guardLogging(void Function() body) {
  try {
    body();
    return true;
  } on Object catch (error) {
    if (!_reportingFailure) {
      _reportingFailure = true;
      try {
        debugPrint('tidy_log: could not log (${error.runtimeType})');
      } on Object {
        // Nowhere left to report it.
      } finally {
        _reportingFailure = false;
      }
    }
    return false;
  }
}

/// The app-facing logger.
///
/// Every line it prints starts with an ANSI reset when colours are on. The
/// `tidy_log` runner uses that marker to pass these lines through
/// untouched instead of restyling them a second time.
abstract final class TidyLog {
  static var _projectPackages = const <String>['app'];
  static var _minLevel = Level.debug;
  static var _enabled = kDebugMode;
  static var _color = true;
  static LinePrinter _printer = _defaultPrinter;
  static var _redactor = Redactor(TidyConfig.defaultRedactKeys);
  static FlutterErrorFormatter? _errorFormatter;
  static var _httpBodies = HttpBodies.always;
  static var _httpRules = const <ResponseRule>[];

  /// The `keepStructuredErrors` the hooks were installed with; null until
  /// [installErrorHooks] has taken over.
  static bool? _hooksStructured;

  /// Sets up the logger. Call it once, before [installErrorHooks].
  ///
  /// [projectPackages] lists your own packages; the first one is the app and
  /// its paths print as `lib/…`. Frames from these packages lead stack traces.
  ///
  /// [errorText] gives your own error types a short one-line description
  /// (return null to fall back). DioException and PlatformException already
  /// have one.
  ///
  /// [httpBodies] decides which HTTP calls print their body and response
  /// (default: all of them). [httpRules] classify responses by their body for
  /// every [TidyDioInterceptor] that has no rules of its own.
  static void configure({
    List<String>? projectPackages,
    Level? minLevel,
    bool? enabled,
    bool? color,
    List<String>? redactKeys,
    LinePrinter? printer,
    ErrorText? errorText,
    HttpBodies? httpBodies,
    List<ResponseRule>? httpRules,
  }) {
    if (projectPackages != null && projectPackages.isNotEmpty) _projectPackages = List.unmodifiable(projectPackages);
    if (minLevel != null) _minLevel = minLevel;
    if (enabled != null) _enabled = enabled;
    if (color != null) _color = color;
    if (redactKeys != null) _redactor = Redactor(redactKeys);
    if (printer != null) _printer = printer;
    if (errorText != null) customErrorText = errorText;
    if (httpBodies != null) _httpBodies = httpBodies;
    if (httpRules != null) _httpRules = List.unmodifiable(httpRules);
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
    customErrorText = null;
    _httpBodies = HttpBodies.always;
    _httpRules = const [];
    _errorFormatter = null;
    // Tests put the handlers back themselves; this only lets them install
    // the hooks again.
    _hooksStructured = null;
  }

  static List<String> get projectPackages => _projectPackages;
  static HttpBodies get httpBodies => _httpBodies;
  static List<ResponseRule> get httpRules => _httpRules;

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
    guardLogging(() => _log(level, message, tag: tag, error: error, stackTrace: stackTrace));
  }

  static void _log(Level level, Object? message, {String? tag, Object? error, StackTrace? stackTrace}) {
    if (!_enabled || level.index < _minLevel.index) return;
    // An error passed as the message (the uncaught-error hook does this)
    // gets the same short description as one passed as `error`.
    final asMessage = message is String || message == null ? null : describeError(message);
    final described = error == null ? null : describeError(error);
    _emit(
      formatRecord(
        level: level,
        message: _redactor.apply(asMessage?.first ?? '$message'),
        projectPackages: _projectPackages,
        tag: tag,
        error: error,
        errorText: error == null ? null : _redactor.apply(described?.first ?? '$error'),
        stackTrace: stackTrace,
        notes: [
          for (final note in [...?asMessage?.skip(1), ...?described?.skip(1)]) _redactor.apply(note),
        ],
      ),
    );
  }

  /// Prints a prepared [Entry]. Used by the error hooks and the Dio
  /// interceptor; most code calls [log] instead. With a [level], entries
  /// below `minLevel` are dropped.
  static void emit(Entry entry, {Level? level}) {
    guardLogging(() => _emit(entry, level: level));
  }

  static void _emit(Entry entry, {Level? level}) {
    if (!_enabled || (level != null && level.index < _minLevel.index)) return;
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
  /// whether an uncaught async error counts as handled. An error the logger
  /// did not print (below `minLevel`, or logging failed) counts as unhandled
  /// unless that handler says otherwise, so the engine still reports it.
  ///
  /// In debug runs the widget inspector replaces [FlutterError.presentError]
  /// with its structured-error reporter as soon as the binding starts, and
  /// the Flutter tool then prints `Another exception was thrown: …` without
  /// a location for every error after the first. So the handler calls the
  /// tidy formatter directly. Pass [keepStructuredErrors] to route errors
  /// through `presentError` instead (IDE error links, DevTools' error list).
  ///
  /// When the logger is disabled (profile and release builds unless
  /// `configure(enabled: true)`, or `configure(enabled: false)`), this does
  /// nothing, so Flutter's own error output and the engine's unhandled-error
  /// report stay as they are. If the logger is disabled after the hooks are
  /// installed, they hand each error to the presenter and async handler they
  /// replaced instead of printing it. Calling this again does nothing; a
  /// different [keepStructuredErrors] on the second call is ignored, with a
  /// one-line hint.
  static void installErrorHooks({bool keepStructuredErrors = false}) {
    if (!_enabled) return;
    final installed = _hooksStructured;
    if (installed != null) {
      if (installed != keepStructuredErrors) {
        _hint('installErrorHooks() was already called with keepStructuredErrors: $installed; this call is ignored.');
      }
      return;
    }
    _hooksStructured = keepStructuredErrors;

    // Read onError first: Dart initialises it lazily from presentError, so
    // reading it after the assignment below would return our own presenter.
    final current = FlutterError.onError;
    final defaultPresenter = FlutterError.presentError;
    void present(FlutterErrorDetails details) {
      if (!_enabled) {
        defaultPresenter(details);
        return;
      }
      (_errorFormatter ??= FlutterErrorFormatter()).present(details);
    }

    FlutterError.presentError = present;
    if (current == null || current == FlutterError.dumpErrorToConsole || current == defaultPresenter) {
      FlutterError.onError = keepStructuredErrors ? (details) => FlutterError.presentError(details) : present;
    } else {
      _hint('FlutterError.onError was already set. Call TidyLog.installErrorHooks() before your crash reporter.');
    }

    final previous = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (error, stack) {
      final printed =
          _enabled &&
          Level.error.index >= _minLevel.index &&
          guardLogging(() => _log(Level.error, error, tag: 'uncaught', stackTrace: stack));
      return previous?.call(error, stack) ?? printed;
    };
  }

  static void _hint(String text) =>
      emit(Entry(head: [Level.warning.labelSpan, Span(text, Tone.warning)], source: 'tidy_log'));

  static void _defaultPrinter(String line) => debugPrint(line);
}
