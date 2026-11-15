import 'package:dio/dio.dart';
import 'package:tidy_log_core/tidy_log_core.dart';

import 'error_text.dart';
import 'tidy_log.dart';

const _startKey = 'tidy_log.start';

/// Logs each Dio request as one compact entry when it finishes:
/// ```
/// POST /api/Auth/Signin  10.0.2.2:4013  401  1,003 ms · 15:21:09
///     body  {userId: 1, pin: ••••••••}
///     resp  {"error":"bad pin"}
/// ```
/// Values of the configured redaction keys are masked. Add it instead of a
/// Dio pretty logger: `dio.interceptors.add(TidyDioInterceptor())`.
final class TidyDioInterceptor extends Interceptor {
  TidyDioInterceptor({this.logBodies = true, DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final bool logBodies;
  final DateTime Function() _clock;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.extra[_startKey] = _clock();
    handler.next(options);
  }

  @override
  void onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) {
    _log(response.requestOptions, status: response.statusCode, response: response.data);
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final response = err.response;
    if (response != null) {
      _log(err.requestOptions, status: response.statusCode, response: response.data);
    } else {
      _log(err.requestOptions, error: dioReason(err));
    }
    handler.next(err);
  }

  void _log(RequestOptions options, {int? status, Object? response, String? error}) {
    final start = options.extra[_startKey];
    final now = _clock();
    final entry = httpEntry(
      method: options.method,
      url: options.uri.toString(),
      status: status,
      error: error,
      durationMs: start is DateTime ? now.difference(start).inMilliseconds : null,
      time: start is DateTime ? _hms(start) : null,
      body: logBodies && options.data != null ? TidyLog.redact('${options.data}') : null,
      response: logBodies && response != null ? TidyLog.redact('$response') : null,
    );
    TidyLog.emit(entry);
  }

  static String _hms(DateTime t) => [t.hour, t.minute, t.second].map((v) => '$v'.padLeft(2, '0')).join(':');
}
