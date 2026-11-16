import 'dart:convert';

import 'package:yaml/yaml.dart';

import 'http_entry.dart';

/// What a [FieldRule] decided about one response body.
final class FieldVerdict {
  const FieldVerdict(this.outcome, {this.message, required this.rule});

  final HttpOutcome outcome;

  /// The human-readable text at the rule's message path, if any.
  final String? message;

  /// Which rule decided and why: `type = 3 → error`.
  final String rule;
}

/// Maps the value at [path] in a JSON body to an outcome. Shared by the
/// in-app `ResponseRule.field` and `http_rules` in `tidy_log.yaml`, so both
/// judge a body the same way.
///
/// Matching is lenient, because backends are inconsistent: `2` matches
/// `'2'`, and strings match case-insensitively. A value that is present but
/// not in [values] gets [otherwise], or no verdict when that is null; a
/// missing field never gets a verdict. [message] is a path to a
/// human-readable text (a string, or the first item of a list).
final class FieldRule {
  const FieldRule(this.path, this.values, {this.message, this.otherwise});

  final String path;
  final Map<Object?, HttpOutcome> values;
  final String? message;
  final HttpOutcome? otherwise;

  FieldVerdict? decide(Object? body) {
    final (found, value) = lookup(body, path);
    if (!found) return null;
    final outcome = _match(value) ?? otherwise;
    if (outcome == null) return null;
    return FieldVerdict(
      outcome,
      message: message == null ? null : textAt(body, message!),
      rule: '$path = ${value is String ? '"$value"' : '$value'} → ${outcome.name}',
    );
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
}

/// The response body as JSON: a decoded Map or List as is, or JSON text
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

/// A body printed one field per line (`type: 3`, nested fields indented,
/// list items as `- `), as the runner reads it from a pretty_dio_logger
/// box, back as maps and lists so a [FieldRule] can judge it.
///
/// Those lines are nearly YAML, so they are read as YAML. When they are not
/// valid YAML (a value with `: ` in it, for example), only the top-level
/// `key: value` lines are kept.
Object? bodyFromLines(List<String> lines) {
  if (lines.isEmpty) return null;
  try {
    return loadYaml(lines.join('\n'));
  } on FormatException {
    return {
      for (final line in lines)
        if (RegExp(r'^([^\s:-][^:]*):\s?(.*)$').firstMatch(line) case final m?) m[1]!: _scalar(m[2]!),
    };
  }
}

Object? _scalar(String text) {
  try {
    final value = loadYaml(text);
    return value is Map || value is List ? text : value;
  } on FormatException {
    return text;
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
    final List<Object?> list => list.whereType<Object>().firstOrNull?.toString(),
    _ => '$value',
  };
  return text == null || text.trim().isEmpty ? null : text.trim();
}
