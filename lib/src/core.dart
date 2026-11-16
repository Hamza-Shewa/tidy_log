/// Pure-Dart core of tidy_log: styled entries, the stack trimmer and the
/// logcat cleaner pipeline used by the `tidy_log` runner (`dart run tidy_log`).
library;

export 'core/console/config.dart' show LabelRule, Preset, TidyConfig, quietMessages, quietTags;
export 'core/console/pipeline.dart' show ConsolePipeline;
export 'core/console/redactor.dart' show Redactor;
export 'core/entry.dart' show Entry, Span, Tone;
export 'core/flutter_messages.dart' show followOnKind, isFollowOnError, stripRenderIds;
export 'core/http_entry.dart' show HttpOutcome, cap, httpEntry, httpOutcome, thousands;
export 'core/java_stack.dart' show JavaStack, isJavaException, javaSdkPrefixes, parseJavaStack, shortJavaException;
export 'core/level.dart' show Level;
export 'core/record_formatter.dart' show formatRecord, stackDetails;
export 'core/renderer.dart' show Renderer, startsWithAnsi, stripAnsi;
export 'core/stack_trimmer.dart' show FrameRef, TrimmedStack, displayPath, trimStack, trimStackText;
