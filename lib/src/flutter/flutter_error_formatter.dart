import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:stack_trace/stack_trace.dart';
import '../core.dart';

import 'error_text.dart';
import 'tidy_log.dart';

final _sourceLocation = RegExp(r'((?:package:|file://)\S+?\.dart):(\d+):(\d+)');

/// Folders that hold dependencies and SDKs, never your own code: the pub
/// cache (`.pub-cache`, Windows `Pub/Cache`), the Flutter SDK packages (also
/// under FVM) and the engine's `bin/cache`.
final _outsideProject = RegExp(r'/(?:\.pub-cache|pub/cache|bin/cache|\.dart_tool)/|/packages/flutter\w*/lib/');

/// Whether [file], a widget's creation location (`file:///…` or
/// `package:…`), is your own source rather than a dependency or the SDK.
@visibleForTesting
bool isProjectSourceFile(String file, {List<String> projectPackages = const []}) {
  final uri = Uri.tryParse(file);
  if (uri == null) return false;
  if (uri.scheme == 'package') {
    return uri.pathSegments.isNotEmpty && projectPackages.contains(uri.pathSegments.first);
  }
  return !_outsideProject.hasMatch(uri.path.replaceAll(r'\', '/').toLowerCase());
}

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

  /// Prints [details]. Never throws: a failure while formatting prints one
  /// fallback line instead (see `TidyLog`).
  void present(FlutterErrorDetails details) {
    guardLogging(() => _present(details));
  }

  void _present(FlutterErrorDetails details) {
    final described = describeError(details.exception);
    final lines = described ?? details.exceptionAsString().split('\n').where((l) => l.trim().isNotEmpty).toList();
    // Masked here, once, so no path below (`thrown again`, follow-on counts)
    // can print the raw text.
    final message = TidyLog.redact(stripRenderIds(lines.isEmpty ? 'Flutter error' : lines.first.trim()));

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
    // The widget location and the context are extras: if building them
    // throws, the error is still printed without them.
    final widget = _orNull(() => _widgetLocation(details, packages));
    if (widget != null && !stack.inProject) {
      stack = TrimmedStack(location: widget, trail: stack.trail, hidden: stack.hidden);
    }

    final context = _orNull(() => details.context?.toDescription());
    TidyLog.emit(
      formatRecord(
        level: Level.error,
        message: message,
        projectPackages: packages,
        tag: source == null ? null : 'caught by $source',
        trimmed: stack,
        notes: [
          for (final note in [
            if (context != null && context.isNotEmpty) context,
            for (final line in lines.skip(1).take(3)) stripRenderIds(line.trim()),
          ])
            TidyLog.redact(note),
        ],
      ),
    );
  }

  static T? _orNull<T>(T? Function() build) {
    try {
      return build();
    } on Object {
      return null;
    }
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

  /// Where in your code the failing widget was created, for errors whose
  /// stack has no frame of yours (build, layout and paint errors).
  static FrameRef? _widgetLocation(FlutterErrorDetails details, List<String> packages) {
    final info = details.informationCollector?.call().toList() ?? const <DiagnosticsNode>[];
    return _nearestProjectWidget(info, packages) ?? _describedWidget(info, packages);
  }

  /// Debug builds attach the failing element as a [DebugCreator]. Flutter's
  /// own "relevant error-causing widget" text is only derived from it later,
  /// and without the IDE's project folders it names any widget outside
  /// `package:flutter` (a pub-cache widget, for instance). So walk up from
  /// the element to the nearest widget created in your own code.
  static FrameRef? _nearestProjectWidget(List<DiagnosticsNode> info, List<String> packages) {
    for (final node in info) {
      final creator = node.value;
      if (creator is! DebugCreator) continue;
      final found = _orNull(() {
        FrameRef? hit;
        var visited = 0;
        bool visit(Element element) {
          hit = _projectCreation(element.widget, packages);
          return hit == null && ++visited < 500;
        }

        if (visit(creator.element)) creator.element.visitAncestorElements(visit);
        return hit;
      });
      if (found != null) return found;
    }
    return null;
  }

  /// [widget]'s creation location when it is in your code. Read through the
  /// inspector's serializer: `CreationLocation.of` only exists from Flutter
  /// 3.50 on, and the serializer works on every supported version.
  static FrameRef? _projectCreation(Widget widget, List<String> packages) {
    // ignore: invalid_use_of_visible_for_testing_member
    final delegate = InspectorSerializationDelegate(service: WidgetInspectorService.instance, subtreeDepth: 0);
    final location = widget.toDiagnosticsNode().toJsonMap(delegate)['creationLocation'];
    if (location is! Map) return null;
    final file = location['file'];
    if (file is! String || !isProjectSourceFile(file, projectPackages: packages)) return null;
    final path = displayPath(Uri.parse(file), appPackage: packages.first);
    return FrameRef('$path:${location['line']}:${location['column']}', widget.runtimeType.toString());
  }

  /// Fallback for errors that already carry the "relevant error-causing
  /// widget" text. Only used when that widget is in your own code.
  static FrameRef? _describedWidget(List<DiagnosticsNode> info, List<String> packages) {
    final text = info.map((n) => n.toStringDeep()).join('\n');
    final start = text.indexOf('relevant error-causing widget');
    if (start < 0) return null;
    final after = text.substring(start);
    final match = _sourceLocation.firstMatch(after);
    if (match == null || !isProjectSourceFile(match[1]!, projectPackages: packages)) return null;
    final widget = after
        .split('\n')
        .skip(1)
        .firstWhere((l) => l.trim().isNotEmpty, orElse: () => '')
        .trim()
        .split(' ')
        .first;
    final path = displayPath(Uri.parse(match[1]!), appPackage: packages.first);
    return FrameRef('$path:${match[2]}:${match[3]}', widget);
  }
}
