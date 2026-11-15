import 'entry.dart';

/// Log severity shared by the in-app logger and the logcat cleaner.
enum Level {
  verbose('VRB'),
  debug('DBG'),
  info('INF'),
  warning('WRN'),
  error('ERR'),
  fatal('FTL');

  const Level(this.label);

  /// Three-letter label shown at the start of a line.
  final String label;

  /// Maps a logcat priority letter (`V`, `D`, `I`, `W`, `E`, `F`/`A`).
  static Level fromLogcat(String letter) => switch (letter) {
    'V' => verbose,
    'D' => debug,
    'I' => info,
    'W' => warning,
    'E' => error,
    _ => fatal,
  };

  bool get isQuiet => index <= debug.index;

  Tone get labelTone => switch (this) {
    verbose || debug || info => Tone.dim,
    warning => Tone.warning,
    error || fatal => Tone.errorBold,
  };

  Tone get messageTone => switch (this) {
    verbose || debug => Tone.dim,
    info => Tone.plain,
    warning => Tone.warning,
    error || fatal => Tone.error,
  };

  /// The `ERR ` style label span (padded to a fixed width).
  Span get labelSpan => Span('$label ', labelTone);
}
