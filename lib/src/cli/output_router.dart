import 'dart:convert';

import '../core/console/pipeline.dart';
import '../core/entry.dart';
import '../core/renderer.dart';

/// Routes the Flutter tool's stdout lines.
///
/// `flutter run --machine` JSON (`[{"event":…}]`) is what the debug adapter
/// talks; it goes to [styled] unchanged. Every other line is device or tool
/// output, which runs through the [ConsolePipeline]. Each resulting entry is
/// written styled to [styled] and as plain text to [plain] (the clean copy).
final class OutputRouter {
  OutputRouter({
    required this.pipeline,
    required this.styled,
    this.plain,
    Renderer? styledRenderer,
  }) : _styledRenderer =
           styledRenderer ?? Renderer(color: pipeline.config.color, maxHeadWidth: pipeline.config.maxWidth),
       _plainRenderer = const Renderer(color: false);

  final ConsolePipeline pipeline;
  final void Function(String line) styled;
  final void Function(String line)? plain;
  final Renderer _styledRenderer;
  final Renderer _plainRenderer;

  /// Returns true when [line] went through the pipeline (so the caller knows
  /// to schedule a [flush]).
  bool add(String line) {
    if (isDaemonMessage(line)) {
      styled(line);
      return false;
    }
    _write(pipeline.add(line));
    return true;
  }

  void flush() => _write(pipeline.flush());

  void _write(List<Entry> entries) {
    for (final entry in entries) {
      _styledRenderer.render(entry).forEach(styled);
      final plainSink = plain;
      if (plainSink != null) _plainRenderer.render(entry).forEach(plainSink);
    }
  }

  /// The same test the Flutter debug adapter uses: a JSON list holding one
  /// map.
  static bool isDaemonMessage(String line) {
    final trimmed = line.trim();
    if (!trimmed.startsWith('[') || !trimmed.endsWith(']')) return false;
    try {
      final decoded = jsonDecode(trimmed);
      return decoded is List && decoded.length == 1 && decoded.first is Map;
    } on FormatException {
      return false;
    }
  }
}
