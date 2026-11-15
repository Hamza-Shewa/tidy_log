import 'package:stack_trace/stack_trace.dart';

/// A stack frame reduced to what the console shows.
final class FrameRef {
  const FrameRef(this.location, this.member);

  /// `lib/app/view/home_page.dart:145:12` for the app package,
  /// `package:core_kit/…/x.dart:42:5` for other packages.
  final String location;

  /// `HomePage._onTap`.
  final String member;

  @override
  String toString() => '$location  $member';
}

/// The interesting part of a stack trace: where it happened, a short trail of
/// your own frames, and how many other frames were left out.
final class TrimmedStack {
  const TrimmedStack({required this.location, required this.trail, required this.hidden, this.inProject = false});

  static const empty = TrimmedStack(location: null, trail: [], hidden: 0);

  final FrameRef? location;

  /// Whether [location] is one of your own frames (rather than a fallback).
  final bool inProject;
  final List<FrameRef> trail;
  final int hidden;
}

/// Picks frames from [trace] that belong to [projectPackages].
///
/// The first package in [projectPackages] is the app itself and is shown as
/// `lib/…`. When no frame belongs to the project, the first frame outside the
/// Dart and Flutter SDKs is used, and failing that the top frame.
TrimmedStack trimStack(Trace trace, {required List<String> projectPackages, int maxTrail = 4}) {
  final frames = trace.frames.where((f) => f.uri.toString().isNotEmpty).toList();
  if (frames.isEmpty) return TrimmedStack.empty;

  bool isProject(Frame f) => f.package != null && projectPackages.contains(f.package);
  bool isSdk(Frame f) => f.isCore || f.package == 'flutter' || f.package == 'stack_trace';

  var index = frames.indexWhere(isProject);
  final inProject = index >= 0;
  if (index < 0) index = frames.indexWhere((f) => !isSdk(f));
  if (index < 0) index = 0;

  final trail = frames
      .skip(index + 1)
      .where(isProject)
      .take(maxTrail)
      .map((f) => _ref(f, projectPackages))
      .toList();
  return TrimmedStack(
    location: _ref(frames[index], projectPackages),
    trail: trail,
    hidden: frames.length - 1 - trail.length,
    inProject: inProject,
  );
}

/// Parses [text] (for example a stack printed with `print(stackTrace)`) and
/// trims it. Returns [TrimmedStack.empty] when nothing parses.
TrimmedStack trimStackText(String text, {required List<String> projectPackages}) {
  try {
    return trimStack(Trace.parse(text), projectPackages: projectPackages);
  } on FormatException {
    return TrimmedStack.empty;
  }
}

FrameRef _ref(Frame frame, List<String> projectPackages) {
  final path = displayPath(frame.uri, appPackage: projectPackages.isEmpty ? null : projectPackages.first);
  final line = frame.line == null ? '' : ':${frame.line}${frame.column == null ? '' : ':${frame.column}'}';
  return FrameRef('$path$line', frame.member ?? '<fn>');
}

/// `package:app/x.dart` becomes `lib/x.dart` when `app` is [appPackage], so
/// VS Code can open it from the console. Other URIs keep their package form.
String displayPath(Uri uri, {String? appPackage}) {
  if (uri.scheme == 'package' && uri.pathSegments.isNotEmpty) {
    if (uri.pathSegments.first == appPackage) {
      return 'lib/${uri.pathSegments.skip(1).join('/')}';
    }
    return uri.toString();
  }
  if (uri.scheme == 'file') {
    final path = uri.path;
    final lib = path.lastIndexOf('/lib/');
    return lib >= 0 ? path.substring(lib + 1) : path;
  }
  return uri.toString();
}
