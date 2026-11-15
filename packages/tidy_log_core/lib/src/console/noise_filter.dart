import '../level.dart';
import 'config.dart';
import 'logcat_line.dart';

/// Decides which native logcat lines are shown. Dart lines (`I/flutter`) are
/// never hidden here.
final class NoiseFilter {
  NoiseFilter(TidyConfig config)
    : _minLevel = config.minNativeLevel,
      _hide = [
        for (final glob in [if (config.preset == Preset.quiet) ...quietTags, ...config.hideTags]) _glob(glob),
      ],
      _show = [for (final glob in config.showTags) _glob(glob)],
      _messages = [
        for (final p in [if (config.preset == Preset.quiet) ...quietMessages, ...config.hideMessages]) RegExp(p),
      ];

  final Level _minLevel;
  final List<RegExp> _hide;
  final List<RegExp> _show;
  final List<RegExp> _messages;

  bool shows(LogcatLine line) {
    if (line.isDart) return true;
    if (_show.any((p) => p.hasMatch(line.tag))) return true;
    if (line.level.index < _minLevel.index) return false;
    if (_hide.any((p) => p.hasMatch(line.tag))) return false;
    return !_messages.any((p) => p.hasMatch(line.message));
  }

  static RegExp _glob(String glob) => RegExp('^${glob.split('*').map(RegExp.escape).join('.*')}\$');
}
