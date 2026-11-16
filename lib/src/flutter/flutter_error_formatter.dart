import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:stack_trace/stack_trace.dart';
import '../core.dart';

import 'error_text.dart';
import 'tidy_log.dart';

final _sourceLocation = RegExp(r'((?:package:|file://)\S+?\.dart):(\d+):(\d+)');

/// Formats [FlutterErrorDetails] in the tidy layout.
///
/// The first time a message is seen it prints the message, a few lines of
/// explanation and where it happened. The same message again in a row prints
/// one short `thrown again` line, which the wrapper then counts.
///
/// Errors that Flutter reports only as a side effect of the one before (the
/// dozen `RenderBox was not laid out` after an unbounded-height error) are
/// counted while they keep arriving within [followOnWindow] of each other,
/// and summed up in one dim line.
final class FlutterErrorFormatter {
  FlutterErrorFormatter({this.followOnWindow = const Duration(milliseconds: 500)});

  final Duration followOnWindow;

  String? _last;
  Timer? _window;
  int _followOns = 0;
  String? _followOnKind;

  void present(FlutterErrorDetails details) {
    final described = describeError(details.exception);
    final lines = described ?? details.exceptionAsString().split('\n').where((l) => l.trim().isNotEmpty).toList();
    final message = stripRenderIds(lines.isEmpty ? 'Flutter error' : lines.first.trim());

    if (_window != null && isFollowOnError(message)) {
      _followOns++;
      _followOnKind ??= followOnKind(message);
      _openWindow();
      return;
    }
    _flushFollowOns();
    _openWindow();

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
          for (final line in lines.skip(1).take(3)) TidyLog.redact(stripRenderIds(line.trim())),
        ],
      ),
    );
  }

  void _openWindow() {
    _window?.cancel();
    _window = Timer(followOnWindow, _flushFollowOns);
  }

  void _flushFollowOns() {
    _window?.cancel();
    _window = null;
    final count = _followOns;
    if (count == 0) return;
    final kind = _followOnKind;
    _followOns = 0;
    _followOnKind = null;
    TidyLog.emit(
      Entry(head: [Span('    ┊ +$count follow-on ${count == 1 ? 'error' : 'errors'} hidden ($kind)', Tone.dim)]),
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
