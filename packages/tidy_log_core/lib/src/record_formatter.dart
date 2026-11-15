import 'package:stack_trace/stack_trace.dart';

import 'entry.dart';
import 'level.dart';
import 'stack_trimmer.dart';

/// Builds the console entry for one log call or caught error.
///
/// Layout:
/// ```
/// ERR Bad state: no user                                    · HomePage
///     at lib/app/view/home_page.dart:145:12  HomePage._onTap
///     ┊ lib/app/view/home_page.dart:98:5  HomePage.build
///     ┊ … 38 frames hidden
/// ```
Entry formatRecord({
  required Level level,
  required String message,
  required List<String> projectPackages,
  String? tag,
  Object? error,
  StackTrace? stackTrace,
  TrimmedStack? trimmed,
  List<String> notes = const [],
}) {
  final lines = message.split('\n');
  final errorText = error?.toString();
  final stack =
      trimmed ??
      (stackTrace == null || stackTrace == StackTrace.empty
          ? TrimmedStack.empty
          : trimStack(Trace.from(stackTrace), projectPackages: projectPackages));
  final isError = level.index >= Level.error.index;
  return Entry(
    head: [level.labelSpan, Span(lines.first, isError ? Tone.errorBold : level.messageTone)],
    source: tag,
    details: [
      for (final extra in lines.skip(1)) [Span(extra, level.messageTone)],
      if (errorText != null && errorText != message) [Span(errorText.split('\n').first, level.messageTone)],
      for (final note in notes) [Span(note, Tone.secondary)],
      ...stackDetails(stack, level),
    ],
  );
}

/// Detail lines for a trimmed stack: the location first, then the trail.
List<List<Span>> stackDetails(TrimmedStack stack, Level level, {String? hiddenNote}) {
  final location = stack.location;
  if (location == null) return const [];
  final strong = level.index >= Level.error.index ? Tone.errorBold : level.messageTone;
  final hidden = [
    if (stack.hidden > 0) '… ${framesHidden(stack.hidden)}',
    ?hiddenNote,
  ].join(' · ');
  return [
    [Span('at ${location.location}', strong), Span('  ${location.member}', Tone.secondary)],
    for (final frame in stack.trail) [Span('┊ ${frame.location}  ${frame.member}', Tone.dim)],
    if (hidden.isNotEmpty) [Span('┊ $hidden', Tone.dim)],
  ];
}

/// `1 frame hidden`, `3 frames hidden`.
String framesHidden(int n) => n == 1 ? '1 frame hidden' : '$n frames hidden';
