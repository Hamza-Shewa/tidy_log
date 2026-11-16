import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../core.dart';

/// Returns a short, one-line text for [error], or null to fall back to the
/// built-in descriptions and then `toString()`.
typedef ErrorText = String? Function(Object error);

/// Set by `TidyLog.configure(errorText: …)`. Not exported.
ErrorText? customErrorText;

/// Short lines for errors whose `toString()` is long or unhelpful. The first
/// line replaces `toString()`; any others are printed as notes under it.
/// Returns null when there is nothing better than `toString()`. A
/// [customErrorText] hook that throws counts as returning null.
List<String>? describeError(Object error) {
  final custom = _custom(error);
  if (custom != null) return [custom];
  return switch (error) {
    DioException() => ['DioException · ${dioReason(error)}'],
    PlatformException() => _platform(error),
    FlutterError() => _flutter(error),
    _ => null,
  };
}

String? _custom(Object error) {
  try {
    return customErrorText?.call(error);
  } on Object {
    return null;
  }
}

/// What went wrong with a Dio call, in a few words: `receive timeout (1 s)`,
/// `bad response 500`, `connection refused`, `host lookup failed: api.x`.
String dioReason(DioException e) {
  final options = e.requestOptions;
  return switch (e.type) {
    DioExceptionType.connectionTimeout => 'connect timeout${_seconds(options.connectTimeout)}',
    DioExceptionType.sendTimeout => 'send timeout${_seconds(options.sendTimeout)}',
    DioExceptionType.receiveTimeout => 'receive timeout${_seconds(options.receiveTimeout)}',
    DioExceptionType.badCertificate => 'bad certificate',
    DioExceptionType.badResponse => 'bad response ${e.response?.statusCode ?? ''}'.trim(),
    DioExceptionType.cancel => 'cancelled',
    DioExceptionType.connectionError => _inner(e.error) ?? 'connection error',
    DioExceptionType.unknown => _inner(e.error) ?? _message(e.message) ?? 'unknown error',
    // Types added in later Dio versions (transformTimeout in 5.10+), by name:
    // `transformTimeout` → `transform timeout`.
    _ => e.type.name.replaceAllMapped(RegExp('[A-Z]'), (m) => ' ${m[0]!.toLowerCase()}'),
  };
}

final _hostLookup = RegExp(r"Failed host lookup: '([^']+)'");

/// The useful part of the error Dio wraps. Text-based, so it also works
/// where `dart:io` does not exist.
String? _inner(Object? error) {
  if (error == null) return null;
  final text = '$error'.split(' (OS Error').first.trim();
  final host = _hostLookup.firstMatch(text);
  if (host != null) return 'host lookup failed: ${host[1]}';
  if (text.startsWith('SocketException: ')) {
    final rest = text.substring('SocketException: '.length).split(',').first.trim();
    return rest.isEmpty ? 'socket error' : '${rest[0].toLowerCase()}${rest.substring(1)}';
  }
  return text.isEmpty ? null : text;
}

String? _message(String? message) =>
    message == null || message.isEmpty || message == 'null' ? null : message.split('\n').first;

String _seconds(Duration? d) {
  if (d == null) return '';
  final ms = d.inMilliseconds;
  return ms % 1000 == 0 ? ' (${ms ~/ 1000} s)' : ' (${thousands(ms)} ms)';
}

/// The summary line and up to two hint lines; the rest of Flutter's
/// explanation is the same every time and is left out.
List<String> _flutter(FlutterError e) {
  final lines = [
    for (final l in '$e'.split('\n'))
      if (l.trim().isNotEmpty) stripRenderIds(l.trim()),
  ];
  return lines.isEmpty ? ['FlutterError'] : lines.take(3).toList();
}

List<String> _platform(PlatformException e) {
  final message = e.message;
  final stack = e.stacktrace == null ? null : parseJavaStack(e.stacktrace!.split('\n'));
  final note = stack?.note ?? '';
  return [
    'PlatformException(${e.code})${message == null || message.isEmpty ? '' : ': $message'}',
    if (e.details != null) 'details  ${e.details}',
    if (stack != null) 'native at ${stack.frame}',
    if (note.isNotEmpty) '┊ $note',
  ];
}
