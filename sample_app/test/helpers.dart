import 'package:dio/dio.dart';
import 'package:tidy_log_sample/demos/api_demo.dart';
import 'package:tidy_log_sample/demos/dart_error_demo.dart';
import 'package:tidy_log_sample/demos/log_demo.dart';
import 'package:tidy_log_sample/demos/platform_demo.dart';
import 'package:tidy_log_sample/logging/app_logger.dart';
import 'package:tidy_log_sample/platform/native_bridge.dart';
import 'package:tidy_log_sample/scenarios/scenario.dart';

typedef LogRecord = ({String level, String message, String? tag, Object? error, StackTrace? stackTrace});

/// Keeps every call so tests can assert on what was logged.
final class RecordingLogger implements AppLogger {
  final records = <LogRecord>[];

  @override
  void d(String message, {String? tag}) => records.add((level: 'd', message: message, tag: tag, error: null, stackTrace: null));
  @override
  void i(String message, {String? tag}) => records.add((level: 'i', message: message, tag: tag, error: null, stackTrace: null));
  @override
  void w(String message, {String? tag}) => records.add((level: 'w', message: message, tag: tag, error: null, stackTrace: null));
  @override
  void e(String message, {String? tag, Object? error, StackTrace? stackTrace}) =>
      records.add((level: 'e', message: message, tag: tag, error: error, stackTrace: stackTrace));
}

Demos demosWith(AppLogger logger, {Dio? dio, List<String>? printed}) => Demos(
  logs: LogDemo(logger, printer: printed == null ? null : (line, {wrapWidth}) => printed.add(line ?? '')),
  dart: DartErrorDemo(logger),
  api: ApiDemo(dio ?? Dio(), logger),
  platform: PlatformDemo(const NativeBridge(), DefaultBiometrics(), logger),
);
