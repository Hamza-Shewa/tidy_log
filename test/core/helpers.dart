import 'package:tidy_log/src/core.dart';

const plain = Renderer(color: false, includeSource: true);

/// Runs [lines] through a fresh pipeline and returns the plain output,
/// with the native tag suffix kept so tests can check it.
List<String> clean(List<String> lines, {TidyConfig? config, Renderer renderer = plain}) {
  final pipeline = ConsolePipeline(config ?? TidyConfig(projectPackages: const ['app', 'core_kit']));
  final entries = [for (final l in lines) ...pipeline.add(l), ...pipeline.flush()];
  return [for (final e in entries) ...renderer.render(e)];
}

/// Collapses the padding before the `· Tag` suffix so assertions stay short.
List<String> squash(List<String> lines) => [for (final l in lines) l.replaceAll(RegExp(r' {2,}·'), '  ·')];
