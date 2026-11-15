/// Pure-Dart core of tidy_log: styled entries, the stack trimmer and the
/// logcat cleaner pipeline used by the `tidy_flutter` wrapper.
library;

export 'src/console/config.dart' show LabelRule, Preset, TidyConfig, quietMessages, quietTags;
export 'src/console/pipeline.dart' show ConsolePipeline;
export 'src/console/redactor.dart' show Redactor;
export 'src/entry.dart' show Entry, Span, Tone;
export 'src/flutter_messages.dart' show followOnKind, isFollowOnError, stripRenderIds;
export 'src/http_entry.dart' show cap, httpEntry, thousands;
export 'src/java_stack.dart' show JavaStack, isJavaException, javaSdkPrefixes, parseJavaStack, shortJavaException;
export 'src/level.dart' show Level;
export 'src/record_formatter.dart' show formatRecord, stackDetails;
export 'src/renderer.dart' show Renderer, startsWithAnsi, stripAnsi;
export 'src/stack_trimmer.dart' show FrameRef, TrimmedStack, displayPath, trimStack, trimStackText;
