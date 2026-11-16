import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../core/console/config.dart';
import '../core/console/pipeline.dart';
import 'output_router.dart';

const _usage = '''
tidy_flutter: runs `flutter` and cleans up its log output.

Use it as Dart-Code's customTool (see README), or:
  tidy_flutter run -d <device>     same as flutter run, with tidy output
  tidy_flutter rewrite [--plain]   clean a saved log read from stdin

The real flutter comes from TIDY_FLUTTER_BIN, FLUTTER_ROOT or PATH.''';

/// Entry point of `bin/tidy_flutter.dart`. Returns the exit code.
Future<int> runWrapper(List<String> args) async {
  if (args.isEmpty || args.first == '--tidy-help') {
    stdout.writeln(_usage);
    return 0;
  }
  final config = loadConfig(Directory.current, color: Platform.environment.containsKey('NO_COLOR') ? false : null);
  if (args.first == 'rewrite') return _rewrite(config, plain: args.contains('--plain'));

  final flutter = findFlutter();
  if (flutter == null) {
    stderr.writeln('tidy_flutter: could not find the real flutter. Set TIDY_FLUTTER_BIN or FLUTTER_ROOT.');
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
  return TidyConfig.fromYaml(yamlFile.existsSync() ? yamlFile.readAsStringSync() : null, appPackage: name, color: color);
}

/// Finds the real `flutter`, never this wrapper itself.
String? findFlutter({Map<String, String>? environment}) {
  final env = environment ?? Platform.environment;
  final exe = Platform.isWindows ? 'flutter.bat' : 'flutter';
  final self = File(Platform.resolvedExecutable).absolute.path;
  bool usable(String path) => File(path).existsSync() && File(path).absolute.path != self;

  final explicit = env['TIDY_FLUTTER_BIN'];
  if (explicit != null && usable(explicit)) return explicit;
  final root = env['FLUTTER_ROOT'];
  if (root != null && usable('$root/bin/$exe')) return '$root/bin/$exe';
  for (final dir in (env['PATH'] ?? '').split(Platform.isWindows ? ';' : ':')) {
    if (dir.isNotEmpty && usable('$dir/$exe')) return '$dir/$exe';
  }
  return null;
}

Future<int> _rewrite(TidyConfig config, {required bool plain}) async {
  final pipeline = ConsolePipeline(plain ? _withoutColor(config) : config);
  final router = OutputRouter(pipeline: pipeline, styled: stdout.writeln);
  await for (final line in stdin.transform(const Utf8Decoder(allowMalformed: true)).transform(const LineSplitter())) {
    router.add(line);
  }
  router.flush();
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

  IOSink? copy;
  try {
    final dir = Directory('${Directory.current.path}/.dart_tool/tidy_log')..createSync(recursive: true);
    copy = File('${dir.path}/last_run.log').openWrite();
  } on FileSystemException {
    copy = null;
  }

  final router = OutputRouter(
    pipeline: ConsolePipeline(config),
    styled: stdout.writeln,
    plain: copy?.writeln,
  );
  Timer? idle;
  void scheduleFlush() {
    idle?.cancel();
    idle = Timer(const Duration(milliseconds: 200), router.flush);
  }

  final forwarders = <StreamSubscription<Object?>>[
    stdin.listen(process.stdin.add, onDone: () => process.stdin.close(), cancelOnError: false),
    for (final signal in [ProcessSignal.sigint, if (!Platform.isWindows) ProcessSignal.sigterm])
      signal.watch().listen((s) => process.kill(s)),
  ];

  final out = process.stdout
      .transform(const Utf8Decoder(allowMalformed: true))
      .transform(const LineSplitter())
      .listen((line) {
        if (router.add(line)) scheduleFlush();
      })
      .asFuture<void>();
  final err = stderr.addStream(process.stderr);

  final code = await process.exitCode;
  await Future.wait([out, err]);
  idle?.cancel();
  router.flush();
  for (final f in forwarders) {
    unawaited(f.cancel());
  }
  await copy?.flush();
  await copy?.close();
  await stdout.flush();
  return code;
}
