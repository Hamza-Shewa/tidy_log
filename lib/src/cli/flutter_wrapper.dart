import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../core/console/config.dart';
import '../core/console/pipeline.dart';
import 'output_router.dart';
import 'sdk_shim.dart' show shimMarker;

const _usage = '''
tidy_log: runs `flutter` and cleans up its log output.

  dart run tidy_log run -d <device>      same as `flutter run`, with tidy output
  dart run tidy_log attach -d <device>   same as `flutter attach`
  dart run tidy_log rewrite [--plain]    clean a saved log read from stdin
  dart run tidy_log:setup                set up VS Code (see --help)
  dart run tidy_log:setup --sdk          set up Android Studio / IntelliJ

Every other argument goes to flutter unchanged. The real flutter comes
from TIDY_FLUTTER_BIN, FLUTTER_ROOT or PATH.''';

/// Entry point of `bin/tidy_log.dart` (`dart run tidy_log …`). Returns the
/// exit code.
Future<int> runWrapper(List<String> args) async {
  if (args.isEmpty || args.first == '--tidy-help' || args.first == '--help' && args.length == 1) {
    stdout.writeln(_usage);
    return 0;
  }
  final config = loadConfig(Directory.current, color: Platform.environment.containsKey('NO_COLOR') ? false : null);
  if (args.first == 'rewrite') return _rewrite(config, plain: args.contains('--plain'));

  final flutter = findFlutter();
  if (flutter == null) {
    stderr.writeln('tidy_log: could not find the real flutter. Set TIDY_FLUTTER_BIN or FLUTTER_ROOT.');
    return 127;
  }
  return _run(flutter, args, config);
}

/// Reads `tidy_log.yaml` and the app package name from [dir].
TidyConfig loadConfig(Directory dir, {bool? color}) {
  final yamlFile = File('${dir.path}/tidy_log.yaml');
  final pubspec = File('${dir.path}/pubspec.yaml');
  final name = pubspec.existsSync()
      ? (RegExp(r'^name:\s*(\S+)', multiLine: true).firstMatch(pubspec.readAsStringSync())?[1])
      : null;
  return TidyConfig.fromYaml(
    yamlFile.existsSync() ? yamlFile.readAsStringSync() : null,
    appPackage: name,
    color: color,
  );
}

/// Finds the real `flutter`: `TIDY_FLUTTER_BIN`, then `FLUTTER_ROOT`, then
/// `PATH`.
///
/// A tidy_log shim SDK (a folder with a [shimMarker] file) is never returned,
/// because its `bin/flutter` would start this runner again. The real SDK
/// recorded in the shim's marker is used instead, so a shim first on `PATH`
/// still works. A shim whose recorded SDK is missing is skipped.
String? findFlutter({Map<String, String>? environment}) {
  final env = environment ?? Platform.environment;
  final exe = Platform.isWindows ? 'flutter.bat' : 'flutter';

  String? usable(String path) {
    if (!File(path).existsSync()) return null;
    final shimTarget = _shimTarget(path);
    if (shimTarget == null) return path;
    final real = '$shimTarget/bin/$exe';
    return File(real).existsSync() && _shimTarget(real) == null ? real : null;
  }

  final explicit = env['TIDY_FLUTTER_BIN'];
  final root = env['FLUTTER_ROOT'];
  final candidates = [
    ?explicit,
    if (root != null) '$root/bin/$exe',
    for (final dir in (env['PATH'] ?? '').split(Platform.isWindows ? ';' : ':'))
      if (dir.isNotEmpty) '$dir/$exe',
  ];
  for (final candidate in candidates) {
    final found = usable(candidate);
    if (found != null) return found;
  }
  return null;
}

/// When [flutterExe] (symlinks resolved) is a shim's `bin/flutter`, returns
/// the real SDK root recorded in the shim's marker, or '' if none is
/// recorded. Returns null for a plain SDK.
String? _shimTarget(String flutterExe) {
  String root;
  try {
    root = File(File(flutterExe).resolveSymbolicLinksSync()).parent.parent.path;
  } on FileSystemException {
    root = File(flutterExe).absolute.parent.parent.path;
  }
  final marker = File('$root/$shimMarker');
  if (!marker.existsSync()) return null;
  try {
    return marker.readAsStringSync().trim();
  } on FileSystemException {
    return '';
  }
}

/// Whether the runner should pass single keys to flutter, as `flutter run`
/// does in a terminal, so `r` hot-reloads without Enter.
///
/// Only for `run` and `attach` (the command is the first argument that is not
/// a flag, as in the shim), only in a terminal, and never for IDEs, which use
/// `--machine`. Other commands keep line input so their prompts still work.
bool usesRawKeys(List<String> args, {required bool hasTerminal}) {
  if (!hasTerminal || args.contains('--machine')) return false;
  final command = args.firstWhere((a) => !a.startsWith('-'), orElse: () => '');
  return command == 'run' || command == 'attach';
}

/// Turns terminal line mode and echo off, and puts them back as they were.
/// Some terminals refuse the change; input then simply stays line-based.
final class _KeyMode {
  bool? _lineMode;
  bool? _echoMode;

  void enterRaw() {
    try {
      _lineMode = stdin.lineMode;
      _echoMode = stdin.echoMode;
      // On Windows, echo has to go off before line mode does.
      stdin.echoMode = false;
      stdin.lineMode = false;
    } on IOException {
      // Keep whatever mode the terminal accepted; restore() undoes it.
    }
  }

  /// Safe to call more than once.
  void restore() {
    final (line, echo) = (_lineMode, _echoMode);
    _lineMode = _echoMode = null;
    try {
      if (line != null) stdin.lineMode = line;
      if (echo != null) stdin.echoMode = echo;
    } on IOException {
      // The terminal refused; there is nothing more to undo here.
    }
  }
}

Future<int> _rewrite(TidyConfig config, {required bool plain}) async {
  // `… | dart run tidy_log rewrite | head` closes our stdout early. Stop
  // quietly instead of dying with a "Broken pipe" stack trace.
  unawaited(stdout.done.catchError((Object _) => exit(0)));
  final pipeline = ConsolePipeline(plain ? _withoutColor(config) : config);
  final router = OutputRouter(pipeline: pipeline, styled: stdout.writeln);
  await for (final line in stdin.transform(const Utf8Decoder(allowMalformed: true)).transform(const LineSplitter())) {
    router.add(line);
  }
  router.finish();
  await stdout.flush();
  return 0;
}

TidyConfig _withoutColor(TidyConfig c) => TidyConfig(
  preset: c.preset,
  hideTags: c.hideTags,
  showTags: c.showTags,
  hideMessages: c.hideMessages,
  minNativeLevel: c.minNativeLevel,
  projectPackages: c.projectPackages,
  redactKeys: c.redactKeys,
  color: false,
  maxWidth: c.maxWidth,
  rules: c.rules,
);

Future<int> _run(String flutter, List<String> args, TidyConfig config) async {
  final process = await Process.start(flutter, args, environment: {'TIDY_LOG_WRAPPED': '1'});
  final keys = usesRawKeys(args, hasTerminal: stdin.hasTerminal) ? (_KeyMode()..enterRaw()) : null;
  try {
    return await _forward(process, config, onSignal: keys?.restore);
  } finally {
    keys?.restore();
  }
}

/// Forwards stdin and signals to [process] and restyles its output until it
/// exits. [onSignal] runs before a SIGINT or SIGTERM is passed on.
Future<int> _forward(Process process, TidyConfig config, {void Function()? onSignal}) async {
  IOSink? copy;
  try {
    final dir = Directory('${Directory.current.path}/.dart_tool/tidy_log')..createSync(recursive: true);
    copy = File('${dir.path}/last_run.log').openWrite();
  } on FileSystemException {
    copy = null;
  }

  final router = OutputRouter(pipeline: ConsolePipeline(config), styled: stdout.writeln, plain: copy?.writeln);
  Timer? idle;
  void scheduleFlush() {
    idle?.cancel();
    idle = Timer(const Duration(milliseconds: 200), router.flush);
  }

  final forwarders = <StreamSubscription<Object?>>[
    stdin.listen(process.stdin.add, onDone: () => process.stdin.close(), cancelOnError: false),
    for (final signal in [ProcessSignal.sigint, if (!Platform.isWindows) ProcessSignal.sigterm])
      signal.watch().listen((s) {
        onSignal?.call();
        process.kill(s);
      }),
  ];

  final out = process.stdout.transform(const Utf8Decoder(allowMalformed: true)).transform(const LineSplitter()).listen((
    line,
  ) {
    if (router.add(line)) scheduleFlush();
  }).asFuture<void>();
  final err = stderr.addStream(process.stderr);

  final code = await process.exitCode;
  await Future.wait([out, err]);
  idle?.cancel();
  router.finish();
  for (final f in forwarders) {
    unawaited(f.cancel());
  }
  await copy?.flush();
  await copy?.close();
  await stdout.flush();
  return code;
}
