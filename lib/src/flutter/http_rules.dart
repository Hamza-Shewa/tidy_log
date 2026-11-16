import 'dart:convert';

import 'package:dio/dio.dart';
import '../core.dart' show HttpOutcome;

/// Which HTTP calls print their `body` and `resp` lines.
enum HttpBodies {
  /// Every call (the default).
  always,

  /// Only calls whose outcome is a warning or an error: 4xx, 5xx, transport
  /// failures, and responses a [ResponseRule] flagged.
  onFailure,

  /// Never; one line per call.
  never,
}

/// What a [ResponseRule] decided about one response.
final class RuleVerdict {
  const RuleVerdict(this.outcome, {this.message, this.reason});

  final HttpOutcome outcome;

  /// Shown after the status: `200 ✕ <message>`.
  final String? message;

  /// Which rule decided and why, shown on a `rule` line:
  /// `success = false → error`.
  final String? reason;
}

/// Decides how a response went from its body, for backends that answer 200
/// to everything and put the real result in a field:
///
/// ```dart
/// TidyDioInterceptor(rules: [
///   ResponseRule.field('success', {true: HttpOutcome.success, false: HttpOutcome.error}, message: 'message'),
///   ResponseRule.field('response_type', {
///     'SUCCESS': HttpOutcome.success,
///     'WARNING': HttpOutcome.warning,
///     'ERROR': HttpOutcome.error,
///   }, message: 'messages'),
/// ])
/// ```
///
/// Rules only change how the call is logged (colour, level, verdict). They
/// never change what Dio does: nothing is thrown and the response is left
/// alone. The first rule that returns a verdict wins.
abstract class ResponseRule {
  const ResponseRule();

  /// Looks up [path] (dotted, such as `meta.status` or `errors.0.code`) in
  /// the JSON body and maps its value through [values].
  ///
  /// Matching is lenient on purpose, because backends are inconsistent:
  /// `2` matches `'2'`, and strings match case-insensitively. A value that is
  /// present but not in [values] gets [otherwise], or no verdict when that is
  /// null. [message] is a path to a human-readable text (a string, or the
  /// first item of a list). [when] limits the rule to some requests.
  factory ResponseRule.field(
    String path,
    Map<Object?, HttpOutcome> values, {
    String? message,
    HttpOutcome? otherwise,
    bool Function(RequestOptions request)? when,
  }) = _FieldRule;

  /// Your own logic. Return null to leave the call to the next rule.
  factory ResponseRule.custom(
    RuleVerdict? Function(Response<dynamic> response) decide, {
    bool Function(RequestOptions request)? when,
  }) = _CustomRule;

  /// The verdict for [response], or null when this rule has no opinion.
  RuleVerdict? evaluate(Response<dynamic> response);
}

final class _FieldRule extends ResponseRule {
  _FieldRule(this.path, this.values, {this.message, this.otherwise, this.when});

  final String path;
  final Map<Object?, HttpOutcome> values;
  final String? message;
  final HttpOutcome? otherwise;
  final bool Function(RequestOptions request)? when;

  @override
  RuleVerdict? evaluate(Response<dynamic> response) {
    if (when != null && !when!(response.requestOptions)) return null;
    final body = jsonBody(response.data);
    final (found, value) = lookup(body, path);
    if (!found) return null;
    final outcome = _match(value) ?? otherwise;
    if (outcome == null) return null;
    final text = message == null ? null : textAt(body, message!);
    return RuleVerdict(outcome, message: text, reason: '$path = ${_show(value)} → ${outcome.name}');
  }

  HttpOutcome? _match(Object? value) {
    final exact = values[value];
    if (exact != null) return exact;
    final wanted = '$value'.toLowerCase();
    for (final MapEntry(:key, value: outcome) in values.entries) {
      if ('$key'.toLowerCase() == wanted) return outcome;
    }
    return null;
  }

  static String _show(Object? value) => value is String ? '"$value"' : '$value';
}

final class _CustomRule extends ResponseRule {
  _CustomRule(this.decide, {this.when});

  final RuleVerdict? Function(Response<dynamic> response) decide;
  final bool Function(RequestOptions request)? when;

  @override
  RuleVerdict? evaluate(Response<dynamic> response) {
    if (when != null && !when!(response.requestOptions)) return null;
    return decide(response);
  }
}

/// The response body as JSON: Dio's decoded Map or List as is, or JSON text
/// decoded. Anything else, including text that is not JSON, gives null.
Object? jsonBody(Object? data) {
  if (data is Map || data is List) return data;
  if (data is! String) return null;
  final text = data.trim();
  if (!text.startsWith('{') && !text.startsWith('[')) return null;
  try {
    return jsonDecode(text);
  } on FormatException {
    return null;
  }
}

/// Follows a dotted [path] through Maps and Lists (`errors.0.code`).
/// Returns whether the path exists, and the value there (which may be null).
(bool, Object?) lookup(Object? body, String path) {
  Object? current = body;
  for (final segment in path.split('.')) {
    final here = current;
    final index = int.tryParse(segment);
    if (here is Map && here.containsKey(segment)) {
      current = here[segment];
    } else if (here is List && index != null && index >= 0 && index < here.length) {
      current = here[index];
    } else {
      return (false, null);
    }
  }
  return (true, current);
}

/// The text at [path]: a string as is, the first non-null item of a list,
/// anything else through `toString()`. Null when missing or empty.
String? textAt(Object? body, String path) {
  final (found, value) = lookup(body, path);
  if (!found || value == null) return null;
  final text = switch (value) {
    final List<Object?> list => list.firstWhere((v) => v != null, orElse: () => null)?.toString(),
    _ => '$value',
  };
  return text == null || text.trim().isEmpty ? null : text.trim();
}
