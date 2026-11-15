import 'package:flutter/foundation.dart';
import 'package:stack_trace/stack_trace.dart';
import 'package:tidy_log_core/tidy_log_core.dart';

import 'tidy_log.dart';

final _sourceLocation = RegExp(r'((?:package:|file://)\S+?\.dart):(\d+):(\d+)');

/// Formats [FlutterErrorDetails] in the tidy layout.
///
/// The first time a message is seen it prints the message, a few lines of
/// explanation and where it happened. The same message again in a row prints
/// one short `thrown again` line, which the wrapper then counts.
final class FlutterErrorFormatter {
  String? _last;

  void present(FlutterErrorDetails details) {
    final lines = details.exceptionAsString().split('\n').where((l) => l.trim().isNotEmpty).toList();
    final message = lines.isEmpty ? 'Flutter error' : lines.first.trim();
    final source = details.library;

    if (message == _last) {
      TidyLog.emit(Entry(head: [Level.error.labelSpan, Span(message, Tone.error)], source: 'thrown again'));
      return;
    }
    _last = message;

    final packages = TidyLog.projectPackages;
    var stack = details.stack == null
        ? TrimmedStack.empty
        : trimStack(Trace.from(details.stack!), projectPackages: packages);
    final widget = _widgetLocation(details, packages.first);
    if (widget != null && !stack.inProject) {
      stack = TrimmedStack(location: widget, trail: stack.trail, hidden: stack.hidden);
    }

    final context = details.context?.toDescription();
    TidyLog.emit(
      formatRecord(
        level: Level.error,
        message: TidyLog.redact(message),
        projectPackages: packages,
        tag: source == null ? null : 'caught by $source',
        trimmed: stack,
        notes: [
          if (context != null && context.isNotEmpty) context,
          for (final line in lines.skip(1).take(3)) TidyLog.redact(line.trim()),
        ],
      ),
    );
  }

  /// The "relevant error-causing widget" location Flutter adds in debug mode.
  static FrameRef? _widgetLocation(FlutterErrorDetails details, String appPackage) {
    final info = details.informationCollector?.call() ?? const <DiagnosticsNode>[];
    final text = info.map((n) => n.toStringDeep()).join('\n');
    final start = text.indexOf('relevant error-causing widget');
    if (start < 0) return null;
    final after = text.substring(start);
    final match = _sourceLocation.firstMatch(after);
    if (match == null) return null;
    final widget = after.split('\n').skip(1).firstWhere((l) => l.trim().isNotEmpty, orElse: () => '').trim().split(' ').first;
    final path = displayPath(Uri.parse(match[1]!), appPackage: appPackage);
    return FrameRef('$path:${match[2]}:${match[3]}', widget);
  }
}
