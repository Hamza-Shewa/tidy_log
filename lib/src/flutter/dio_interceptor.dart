import 'package:dio/dio.dart';
import '../core.dart';

import 'error_text.dart';
import 'http_rules.dart';
import 'tidy_log.dart';

/// Rules that already threw once, so each is reported a single time.
final _failedRules = Expando<bool>('tidy_log.failedRule');

/// Logs each Dio request as one entry when it finishes:
/// ```
/// POST   /api/Auth/Signin                                200 ✕    52 ms  15:21:09  10.0.2.2:4013
///     ✕ Invalid PIN
///     rule  success = false → error
///     body  userId: 1
///           pin: ••••••••
///     resp  success: false
///           message: Invalid PIN
/// ```
/// The head line holds the method, the path with its query, the status, the
/// duration, the start time and the host. Under it come the reason (a
/// transport error, or the message of a [ResponseRule]), the rule that
/// decided, and the request `body` and the `resp`onse, one field per line.
///
/// The status is green for 2xx, light yellow for 3xx, yellow for 4xx and
/// magenta for 5xx; a rule's error on a lower status is red. Values of the
/// configured redaction keys are masked, in the path too. Add it instead of a
/// Dio pretty logger: `dio.interceptors.add(TidyDioInterceptor())`.
///
/// [rules] classify responses by their body, for backends that answer 200
/// with `success: false` (see [ResponseRule]). When null, the rules from
/// `TidyLog.configure(httpRules: …)` apply. [bodies] overrides
/// `TidyLog.configure(httpBodies: …)` for this client. [logBodies] false is
/// the same as `bodies: HttpBodies.never` and is kept for compatibility.
///
/// Each line is logged at the level of its outcome (success and info at
/// info, then warning, error), so `minLevel` can hide successful calls.
///
/// Logging never changes the call: the request, response or error always
/// goes on to the next handler as it came, even if logging it fails.
final class TidyDioInterceptor extends Interceptor {
  TidyDioInterceptor({this.logBodies = true, this.bodies, this.rules, DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final bool logBodies;
  final HttpBodies? bodies;
  final List<ResponseRule>? rules;
  final DateTime Function() _clock;

  /// When each request started. Kept here rather than in
  /// [RequestOptions.extra], which can be unmodifiable and which other
  /// interceptors may read. Options another interceptor replaced have no
  /// entry and are logged without timing.
  final _started = Expando<DateTime>('tidy_log.start');

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    try {
      guardLogging(() => _started[options] = _clock());
    } finally {
      handler.next(options);
    }
  }

  @override
  void onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) {
    try {
      guardLogging(() => _log(response.requestOptions, response: response));
    } finally {
      handler.next(response);
    }
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    try {
      guardLogging(() {
        final response = err.response;
        if (response != null) {
          _log(err.requestOptions, response: response);
        } else {
          _log(err.requestOptions, error: dioReason(err));
        }
      });
    } finally {
      handler.next(err);
    }
  }

  void _log(RequestOptions options, {Response<dynamic>? response, String? error}) {
    final start = _started[options];
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
      durationMs: start == null ? null : now.difference(start).inMilliseconds,
      time: start == null ? null : _hms(start),
      outcome: verdict?.outcome,
      verdict: verdict?.message,
      rule: verdict?.reason,
      body: show ? _requestData(options.data) : null,
      response: show ? data : null,
      redact: TidyLog.redact,
    );
    TidyLog.emit(entry, level: _level(outcome));
  }

  /// Form uploads as their fields and file names, everything else as is.
  static Object? _requestData(Object? data) => switch (data) {
    FormData() => {
      for (final field in data.fields) field.key: field.value,
      for (final file in data.files) file.key: '<file ${file.value.filename ?? ''} (${file.value.length} bytes)>',
    },
    _ => data,
  };

  /// The first verdict from the rules. A rule that throws is skipped, so a
  /// bug in a rule never hides the call itself, and is reported with a
  /// warning the first time it throws.
  RuleVerdict? _verdict(Response<dynamic> response) {
    for (final rule in rules ?? TidyLog.httpRules) {
      try {
        final verdict = rule.evaluate(response);
        if (verdict != null) return verdict;
      } on Object catch (error) {
        if (_failedRules[rule] == null) {
          _failedRules[rule] = true;
          guardLogging(
            () => TidyLog.w('Response rule failed: ${describeError(error)?.first ?? error}', tag: 'tidy_log'),
          );
        }
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
