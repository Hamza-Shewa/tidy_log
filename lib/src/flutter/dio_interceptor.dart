import 'package:dio/dio.dart';
import '../core.dart';

import 'error_text.dart';
import 'http_rules.dart';
import 'tidy_log.dart';

const _startKey = 'tidy_log.start';

/// Logs each Dio request as one compact entry when it finishes:
/// ```
/// POST /api/Auth/Signin  10.0.2.2:4013  401  1,003 ms · 15:21:09
///     body  {userId: 1, pin: ••••••••}
///     resp  {"error":"bad pin"}
/// ```
/// The status is green for 2xx, cyan for 3xx, yellow for 4xx and red for
/// 5xx. Values of the configured redaction keys are masked. Add it instead
/// of a Dio pretty logger: `dio.interceptors.add(TidyDioInterceptor())`.
///
/// [rules] classify responses by their body, for backends that answer 200
/// with `success: false` (see [ResponseRule]). When null, the rules from
/// `TidyLog.configure(httpRules: …)` apply. [bodies] overrides
/// `TidyLog.configure(httpBodies: …)` for this client. [logBodies] false is
/// the same as `bodies: HttpBodies.never` and is kept for compatibility.
///
/// Each line is logged at the level of its outcome (success and info at
/// info, then warning, error), so `minLevel` can hide successful calls.
final class TidyDioInterceptor extends Interceptor {
  TidyDioInterceptor({this.logBodies = true, this.bodies, this.rules, DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final bool logBodies;
  final HttpBodies? bodies;
  final List<ResponseRule>? rules;
  final DateTime Function() _clock;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.extra[_startKey] = _clock();
    handler.next(options);
  }

  @override
  void onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) {
    _log(response.requestOptions, response: response);
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final response = err.response;
    if (response != null) {
      _log(err.requestOptions, response: response);
    } else {
      _log(err.requestOptions, error: dioReason(err));
    }
    handler.next(err);
  }

  void _log(RequestOptions options, {Response<dynamic>? response, String? error}) {
    final start = options.extra[_startKey];
    final now = _clock();
    final status = response?.statusCode;
    final verdict = response == null ? null : _verdict(response);
    final outcome = verdict?.outcome ?? httpOutcome(status: status, error: error);
    final show = switch (logBodies ? (bodies ?? TidyLog.httpBodies) : HttpBodies.never) {
      HttpBodies.always => true,
      HttpBodies.never => false,
      HttpBodies.onFailure => outcome == HttpOutcome.warning || outcome == HttpOutcome.error,
    };
    final data = response?.data;
    final entry = httpEntry(
      method: options.method,
      url: options.uri.toString(),
      status: status,
      error: error,
      durationMs: start is DateTime ? now.difference(start).inMilliseconds : null,
      time: start is DateTime ? _hms(start) : null,
      outcome: verdict?.outcome,
      verdict: verdict?.message == null ? null : TidyLog.redact(verdict!.message!),
      rule: verdict?.reason == null ? null : TidyLog.redact(verdict!.reason!),
      body: show && options.data != null ? TidyLog.redact('${options.data}') : null,
      response: show && data != null ? TidyLog.redact('$data') : null,
    );
    TidyLog.emit(entry, level: _level(outcome));
  }

  /// The first verdict from the rules. A rule that throws is reported once
  /// and skipped, so a bug in a rule never hides the call itself.
  RuleVerdict? _verdict(Response<dynamic> response) {
    for (final rule in rules ?? TidyLog.httpRules) {
      try {
        final verdict = rule.evaluate(response);
        if (verdict != null) return verdict;
      } on Object catch (error) {
        TidyLog.w('Response rule failed: ${describeError(error)?.first ?? error}', tag: 'tidy_log');
      }
    }
    return null;
  }

  static Level _level(HttpOutcome outcome) => switch (outcome) {
    HttpOutcome.success || HttpOutcome.info => Level.info,
    HttpOutcome.warning => Level.warning,
    HttpOutcome.error => Level.error,
  };

  static String _hms(DateTime t) => [t.hour, t.minute, t.second].map((v) => '$v'.padLeft(2, '0')).join(':');
}
