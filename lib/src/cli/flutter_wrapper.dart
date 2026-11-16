import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../core/console/config.dart';
import '../core/console/pipeline.dart';
import '../core/console/redactor.dart';
import '../core/renderer.dart';
import 'line_assembler.dart';
import 'output_router.dart';
import 'sdk_shim.dart' show shimMarker;

const _usage = '''
tidy_log: runs `flutter` and cleans up its log output.

  dart run tidy_log run -d <device>      same as `flutter run`, with tidy output
  dart run tidy_log attach -d <device>   same as `flutter attach`
  dart run tidy_log rewrite [--plain]    clean a saved log read from stdin
  dart run tidy_log:setup                set up VS Code (see --help)
  dart run tidy_log:setup --sdk          set up Android Studio / IntelliJ

Every other argument goes to flutter unchanged, and every other command
(test, build, doctor, …) runs untouched. The real flutter comes from
TIDY_FLUTTER_BIN, FLUTTER_ROOT or PATH.''';

/// Entry point of `bin/tidy_log.dart` (`dart run tidy_log …`). Returns the
/// exit code.
///
/// Only `run` and `attach` are tidied (see [tidiesCommand]); every other
/// command passes through byte for byte. A mistake in `tidy_log.yaml` is
/// reported on [err] as one line per problem, with exit code 64. [project]
/// is where `tidy_log.yaml` is read from (the current folder by default).
Future<int> runWrapper(List<String> args, {Directory? project, IOSink? err}) async {
  final errors = err ?? stderr;
  if (args.isEmpty || args.first == '--tidy-help' || args.first == '--help' && args.length == 1) {
    stdout.writeln(_usage);
    return 0;
  }
  final rewriting = args.first == 'rewrite';
  TidyConfig? config;
  if (rewriting || tidiesCommand(args)) {
    try {
      config = loadConfig(
        project ?? Directory.current,
        color: Platform.environment.containsKey('NO_COLOR') ? false : null,
      );
    } on FormatException catch (e) {
      errors.writeln(e.message);
      return 64;
    } on FileSystemException catch (e) {
      errors.writeln('tidy_log.yaml: could not read it (${e.message})');
      return 66;
    }
  }
  if (rewriting) return rewrite(config!, plain: args.contains('--plain'));

  final flutter = findFlutter();
  if (flutter == null) {
    errors.writeln('tidy_log: could not find the real flutter. Set TIDY_FLUTTER_BIN or FLUTTER_ROOT.');
    return 127;
  }
  return config == null ? _passThrough(flutter, args) : _run(flutter, args, config);
}

/// Whether the runner tidies the output of `flutter <args>`: only `run` and
/// `attach` do. The command is the first argument that is not a flag, the
/// same test the SDK shim's scripts use. Every other command (`test
/// --machine`, `build`, `doctor`, `pub`) has output that must stay as it is.
bool tidiesCommand(List<String> args) {
  final command = args.firstWhere((a) => !a.startsWith('-'), orElse: () => '');
  return command == 'run' || command == 'attach';
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
bool usesRawKeys(List<String> args, {required bool hasTerminal}) =>
    hasTerminal && !args.contains('--machine') && tidiesCommand(args);

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

/// `dart run tidy_log rewrite`: cleans a saved log read from [input] (stdin
/// by default) and writes it to [out] (stdout). [plain] drops the colours
/// and keeps every other setting, `http_rules` included.
Future<int> rewrite(TidyConfig config, {required bool plain, Stream<List<int>>? input, IOSink? out}) async {
  final console = out ?? stdout;
  // `… | dart run tidy_log rewrite | head` closes our stdout early. Stop
  // quietly instead of dying with a "Broken pipe" stack trace.
  if (out == null) unawaited(stdout.done.catchError((Object _) => exit(0)));
  final pipeline = ConsolePipeline(plain ? config.copyWith(color: false) : config);
  final router = OutputRouter(
    pipeline: pipeline,
    styled: console.writeln,
    styledRenderer: Renderer(color: pipeline.config.color, maxWidth: _stdoutWidth(pipeline.config)),
  );
  final redact = _safely(Redactor(config.redactKeys).apply);
  final lines = (input ?? stdin).transform(const Utf8Decoder(allowMalformed: true)).transform(const LineSplitter());
  await for (final line in lines) {
    _guard(() => router.add(line), onError: () => console.writeln(redact(line)));
  }
  _guard(router.finish);
  await console.flush();
  return 0;
}

/// Runs [step]; if it throws, runs [onError] instead. A line the pipeline
/// cannot handle must never end the run.
void _guard(void Function() step, {void Function()? onError}) {
  try {
    step();
  } on Object {
    onError?.call();
  }
}

/// [redact] that gives back the text as it is if masking itself fails.
String Function(String) _safely(String Function(String) redact) => (text) {
  try {
    return redact(text);
  } on Object {
    return text;
  }
};

/// Runs a command the runner does not tidy, with this process's stdin,
/// stdout and stderr, so its output reaches the terminal or IDE byte for byte
/// (`flutter test --machine` JSON, `build` progress, `pub` prompts).
Future<int> _passThrough(String flutter, List<String> args) async {
  final process = await Process.start(
    flutter,
    args,
    environment: {'TIDY_LOG_WRAPPED': '1'},
    mode: ProcessStartMode.inheritStdio,
  );
  final signals = _forwardSignals(process);
  try {
    return await process.exitCode;
  } finally {
    for (final s in signals) {
      unawaited(s.cancel());
    }
  }
}

/// Passes SIGINT (and SIGTERM, except on Windows) on to [process].
/// [onSignal] runs first.
List<StreamSubscription<ProcessSignal>> _forwardSignals(Process process, [void Function()? onSignal]) => [
  for (final signal in [ProcessSignal.sigint, if (!Platform.isWindows) ProcessSignal.sigterm])
    signal.watch().listen((s) {
      onSignal?.call();
      process.kill(s);
    }),
];

/// Builds the [OutputRouter] for a run; [OutputRouter.new] by default.
typedef RouterFactory =
    OutputRouter Function({
      required ConsolePipeline pipeline,
      required void Function(String line) styled,
      void Function(String line)? plain,
      Renderer? styledRenderer,
    });

Future<int> _run(String flutter, List<String> args, TidyConfig config) async {
  final process = await Process.start(flutter, args, environment: {'TIDY_LOG_WRAPPED': '1'});
  final keys = usesRawKeys(args, hasTerminal: stdin.hasTerminal) ? (_KeyMode()..enterRaw()) : null;
  try {
    return await forwardProcess(process, config, onSignal: keys?.restore);
  } finally {
    keys?.restore();
  }
}

/// Forwards [input] (stdin by default) and signals to [process] and restyles
/// its output until it exits. Returns flutter's exit code.
///
/// stdout goes through an [OutputRouter] to [out] (stdout by default) and,
/// as plain text, to `last_run.log` in [logDir] (`.dart_tool/tidy_log`). A
/// partial line that has waited [partialDelay] for its newline is written
/// as it came, so progress text and prompts show at once. stderr goes to
/// [err] with secrets masked, and into `last_run.log` too. [onSignal] runs
/// before a SIGINT or SIGTERM is passed on; [watchSignals] and [newRouter]
/// are for tests.
Future<int> forwardProcess(
  Process process,
  TidyConfig config, {
  IOSink? out,
  IOSink? err,
  Stream<List<int>>? input,
  String? logDir,
  bool watchSignals = true,
  void Function()? onSignal,
  Duration partialDelay = const Duration(milliseconds: 100),
  RouterFactory newRouter = OutputRouter.new,
}) async {
  final console = out ?? stdout;
  final errors = err ?? stderr;
  IOSink? copy;
  try {
    final dir = Directory(logDir ?? '${Directory.current.path}/.dart_tool/tidy_log')..createSync(recursive: true);
    copy = File('${dir.path}/last_run.log').openWrite();
  } on FileSystemException {
    copy = null;
  }
  final redact = _safely(Redactor(config.redactKeys).apply);
  void copyLine(String line) => copy?.writeln(stripAnsi(redact(line)));

  final router = newRouter(
    pipeline: ConsolePipeline(config),
    styled: console.writeln,
    plain: copy?.writeln,
    styledRenderer: Renderer(color: config.color, maxWidth: out == null ? _stdoutWidth(config) : config.maxWidth),
  );
  Timer? idle;
  void idleFlush() {
    _guard(router.flush);
    // A pretty_dio box that is still arriving stays open through an idle
    // flush for up to 2 s (ConsolePipeline.flush). Flush once more after
    // that, so the box is not held until the next line arrives.
    if (router.pipeline.holdsPartialBox) idle = Timer(const Duration(milliseconds: 2100), idleFlush);
  }

  void scheduleFlush() {
    idle?.cancel();
    idle = Timer(const Duration(milliseconds: 200), idleFlush);
  }

  final stdoutLines = LineAssembler(
    delay: partialDelay,
    onLine: (line, shown) {
      if (shown > 0) {
        // Its start already went out as it came: finish it the same way.
        console.writeln(redact(line.substring(shown)));
        copyLine(line);
        return;
      }
      var piped = false;
      _guard(
        () => piped = router.add(line),
        onError: () {
          console.writeln(redact(line));
          copyLine(line);
        },
      );
      if (piped) scheduleFlush();
    },
    onPartial: (text) {
      // Whatever the pipeline still holds came first.
      idle?.cancel();
      _guard(router.flush);
      console.write(redact(text));
    },
  );
  final stderrLines = LineAssembler(
    delay: partialDelay,
    onLine: (line, shown) {
      errors.writeln(redact(line.substring(shown)));
      copyLine(line);
    },
    onPartial: (text) => errors.write(redact(text)),
  );

  // Writing to flutter's stdin after it has exited fails with a broken
  // pipe. That error must not replace flutter's own exit code.
  unawaited(process.stdin.done.then<void>((_) {}, onError: (Object _) {}));
  final forwarders = <StreamSubscription<Object?>>[
    (input ?? stdin).listen(
      (data) {
        try {
          process.stdin.add(data);
        } on Object {
          // flutter no longer reads its input.
        }
      },
      onError: (Object _) {},
      onDone: () => unawaited(process.stdin.close().then<void>((_) {}, onError: (Object _) {})),
      cancelOnError: false,
    ),
    if (watchSignals) ..._forwardSignals(process, onSignal),
  ];

  Future<void> pump(Stream<List<int>> stream, LineAssembler lines) => stream
      .transform(const Utf8Decoder(allowMalformed: true))
      .forEach(lines.add)
      .then<void>((_) => lines.close(), onError: (Object _) => lines.close());
  final outDone = pump(process.stdout, stdoutLines);
  final errDone = pump(process.stderr, stderrLines);

  final code = await process.exitCode;
  await Future.wait([outDone, errDone]);
  idle?.cancel();
  _guard(router.finish);
  for (final f in forwarders) {
    unawaited(f.cancel());
  }
  await copy?.flush();
  await copy?.close();
  await console.flush();
  return code;
}

/// The widest a styled line may be: the terminal's width when stdout is a
/// terminal (so lines never wrap), otherwise [configured] (`max_width`).
int consoleWidth({required bool hasTerminal, required int columns, required int configured}) =>
    hasTerminal && columns > 0 ? columns : configured;

int _stdoutWidth(TidyConfig config) {
  var columns = 0;
  if (stdout.hasTerminal) {
    try {
      columns = stdout.terminalColumns;
    } on StdoutException {
      columns = 0;
    }
  }
  return consoleWidth(hasTerminal: stdout.hasTerminal, columns: columns, configured: config.maxWidth);
}
