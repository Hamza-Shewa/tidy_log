import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tidy_log/src/cli/flutter_wrapper.dart';
import 'package:tidy_log/src/cli/output_router.dart';
import 'package:tidy_log/src/core/console/config.dart';

late Directory tmp;

void main() {
  setUp(() => tmp = Directory(Directory.systemTemp.createTempSync('tidy_runner_').resolveSymbolicLinksSync()));
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<int> forward(
    FakeProcess process, {
    Capture? out,
    Capture? err,
    TidyConfig? config,
    Stream<List<int>>? input,
    RouterFactory newRouter = OutputRouter.new,
  }) => forwardProcess(
    process,
    config ?? TidyConfig(color: false),
    out: out ?? Capture(),
    err: err ?? Capture(),
    input: input ?? const Stream.empty(),
    logDir: tmp.path,
    watchSignals: false,
    newRouter: newRouter,
  );

  String lastRun() => File('${tmp.path}/last_run.log').readAsStringSync();

  group('forwardProcess', () {
    test('a partial line shows after a short wait, and is not printed twice when it ends', () async {
      final process = FakeProcess();
      final out = Capture();
      final done = forward(process, out: out);

      process.out("Running Gradle task 'assembleDebug'...");
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect('$out', "Running Gradle task 'assembleDebug'...", reason: 'shown before its newline arrives');

      process.out('   12.3s\n');
      process.exit(0);
      expect(await done, 0);

      expect('$out', "Running Gradle task 'assembleDebug'...   12.3s\n");
      expect(lastRun(), contains("Running Gradle task 'assembleDebug'...   12.3s"));
    });

    test('a prompt without a newline shows while flutter waits for the answer', () async {
      final process = FakeProcess();
      final out = Capture();
      final done = forward(process, out: out);

      process.out('[1]: Windows (windows)\n[2]: Chrome (chrome)\nPlease choose one (or "q" to quit): ');
      await Future<void>.delayed(const Duration(milliseconds: 500));

      expect('$out', contains('[2]: Chrome (chrome)\n'), reason: 'the lines before it are flushed first');
      expect('$out', endsWith('Please choose one (or "q" to quit): '));
      process.exit(0);
      await done;
    });

    test('a line that arrives in quick pieces is still restyled as one line', () async {
      final process = FakeProcess();
      final out = Capture();
      final done = forward(process, out: out);

      process.out('E/FlutterSecureStorage(9): decry');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      process.out('ption failed\r\n');
      process.exit(0);
      await done;

      expect('$out', contains('ERR decryption failed'));
      expect('$out', isNot(contains('E/FlutterSecureStorage')));
    });

    test('a line the pipeline cannot handle is printed as it came, masked, and the run goes on', () async {
      final process = FakeProcess();
      final out = Capture();
      final done = forward(process, out: out, newRouter: _FailingRouter.new);

      process.out('I/flutter (1): before\nI/flutter (1): BOOM password=hunter2\nI/flutter (1): after\n');
      process.exit(0);
      expect(await done, 0);

      expect('$out', contains('before'));
      expect('$out', contains('I/flutter (1): BOOM password='));
      expect('$out', isNot(contains('hunter2')));
      expect('$out', contains('after'));
      expect(lastRun(), contains('BOOM password='));
    });

    test('stderr is masked, and copied into last_run.log', () async {
      final process = FakeProcess();
      final err = Capture();
      final done = forward(process, err: err);

      process.err('Error: login failed for password=hunter2\n');
      process.exit(1);
      expect(await done, 1);

      expect('$err', startsWith('Error: login failed for password='));
      expect('$err', isNot(contains('hunter2')));
      expect(lastRun(), contains('Error: login failed for password='));
      expect(lastRun(), isNot(contains('hunter2')));
    });

    test('a key sent after flutter stopped reading does not replace its exit code', () async {
      final process = FakeProcess(stdin: IOSink(_BrokenPipe()));
      final keys = StreamController<List<int>>();
      final done = forward(process, input: keys.stream);

      keys.add(utf8.encode('r'));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      keys.add(utf8.encode('q'));
      await keys.close();
      process.exit(3);

      expect(await done, 3);
    });
  });

  group('runWrapper', () {
    test('a mistake in tidy_log.yaml is one line on stderr and exit code 64', () async {
      File('${tmp.path}/tidy_log.yaml').writeAsStringSync('hide_tags: FlutterGeolocator\n');
      final err = Capture();

      expect(await runWrapper(['run', '-d', 'emulator-5554'], project: tmp, err: err), 64);
      expect('$err', 'tidy_log.yaml: hide_tags: expected a list of strings\n');
    });

    test('invalid YAML is reported with its line, not as a stack trace', () async {
      File('${tmp.path}/tidy_log.yaml').writeAsStringSync('preset: quiet\nhide_tags: [a, b\n');
      final err = Capture();

      expect(await runWrapper(['attach'], project: tmp, err: err), 64);
      expect('$err', startsWith('tidy_log.yaml: not valid YAML (line '));
      expect('$err'.trim().split('\n'), hasLength(1));
    });

    test('rewrite --plain keeps http_rules', () async {
      final config = TidyConfig.fromYaml(
        'http_rules:\n  - field: type\n    values: {1: success}\n    otherwise: error\n',
      );
      final out = Capture();
      final log = [
        ..._box('Request ║ GET ', 'http://h:1/api/balance'),
        ..._box('Response ║ GET ║ Status: 200 OK', 'http://h:1/api/balance', [
          '╔ Body',
          '║    {',
          '║         type: 3',
          '║    }',
          _rule,
        ]),
      ].join('\n');

      expect(await rewrite(config, plain: true, input: Stream.value(utf8.encode('$log\n')), out: out), 0);

      expect('$out', contains('rule  type = 3 → error'));
      expect('$out', isNot(contains('\x1B[')));
    });

    test('only run and attach are tidied', () {
      expect(tidiesCommand(['run', '-d', 'x']), isTrue);
      expect(tidiesCommand(['--no-color', 'attach']), isTrue);
      expect(tidiesCommand(['test', '--machine']), isFalse);
      expect(tidiesCommand(['build', 'apk']), isFalse);
      expect(tidiesCommand(['doctor', '-v']), isFalse);
      expect(tidiesCommand([]), isFalse);
    });
  });

  group('the tidy_log command', () {
    test('passes flutter test --machine through byte for byte, even with a broken tidy_log.yaml', () async {
      final json = jsonEncode({
        'test': {'id': 3, 'name': 'a test name that is long enough ' * 6, 'suiteID': 0, 'groupIDs': <int>[]},
        'type': 'testStart',
        'time': 1234,
      });
      expect(json.length, greaterThan(160));
      final flutter = _fakeFlutter([json, '{"success":true,"type":"done","time":1300}'], exitCode: 1);
      File('${tmp.path}/tidy_log.yaml').writeAsStringSync('hide_tags: oops\n');

      final result = await _runCli(['test', '--machine'], env: {'TIDY_FLUTTER_BIN': flutter});

      expect(result.exitCode, 1, reason: '${result.stderr}');
      expect(const LineSplitter().convert('${result.stdout}'), [json, '{"success":true,"type":"done","time":1300}']);
      expect(result.stderr.toString(), isEmpty);
      expect(File('${tmp.path}/.dart_tool/tidy_log/last_run.log').existsSync(), isFalse);
    });

    test('a broken tidy_log.yaml stops run with one line and exit code 64, no stack trace', () async {
      File('${tmp.path}/tidy_log.yaml').writeAsStringSync('max_width: "120"\ncolor: "no"\n');

      final result = await _runCli(
        ['run', '-d', 'x'],
        env: {
          'TIDY_FLUTTER_BIN': _fakeFlutter(['never runs']),
        },
      );

      expect(result.exitCode, 64);
      expect(const LineSplitter().convert('${result.stderr}'), [
        'tidy_log.yaml: color: expected true or false',
        'tidy_log.yaml: max_width: expected a whole number above 0, such as 120',
      ]);
      expect(result.stdout.toString(), isEmpty);
    });
  });
}

/// A child process the test drives by hand.
final class FakeProcess implements Process {
  FakeProcess({IOSink? stdin}) : stdin = stdin ?? IOSink(_Discard());

  final _out = StreamController<List<int>>();
  final _err = StreamController<List<int>>();
  final _exit = Completer<int>();

  @override
  final IOSink stdin;
  @override
  Stream<List<int>> get stdout => _out.stream;
  @override
  Stream<List<int>> get stderr => _err.stream;
  @override
  Future<int> get exitCode => _exit.future;
  @override
  int get pid => 4242;
  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) => true;

  void out(String text) => _out.add(utf8.encode(text));
  void err(String text) => _err.add(utf8.encode(text));

  void exit(int code) {
    unawaited(_out.close());
    unawaited(_err.close());
    _exit.complete(code);
  }
}

/// Collects what the runner writes.
final class Capture implements IOSink {
  final _buffer = StringBuffer();
  @override
  void write(Object? object) => _buffer.write(object);
  @override
  void writeln([Object? object = '']) => _buffer.writeln(object);
  @override
  Future<void> flush() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
  @override
  String toString() => _buffer.toString();
}

/// Takes whatever is written and drops it.
final class _Discard implements StreamConsumer<List<int>> {
  @override
  Future<void> addStream(Stream<List<int>> stream) => stream.drain<void>();
  @override
  Future<void> close() async {}
}

/// flutter's stdin once flutter has exited: a write fails with a broken pipe.
final class _BrokenPipe implements StreamConsumer<List<int>> {
  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await stream.first;
    throw const FileSystemException('Broken pipe');
  }

  @override
  Future<void> close() async {}
}

/// A router that fails on any line with BOOM in it.
final class _FailingRouter extends OutputRouter {
  _FailingRouter({required super.pipeline, required super.styled, super.plain, super.styledRenderer});

  @override
  bool add(String line) => line.contains('BOOM') ? throw StateError('cannot handle $line') : super.add(line);
}

const _p = 'I/flutter (1): ';
final _rule = '╚${'═' * 128}╝';

/// A pretty_dio_logger box as `flutter run` shows it.
List<String> _box(String header, String url, [List<String> rest = const []]) => [
  _p,
  '$_p╔╣ $header',
  '$_p║  $url',
  '$_p$_rule',
  for (final r in rest) '$_p$r',
];

/// A fake `flutter` in [tmp] that prints [lines] and exits with [exitCode].
String _fakeFlutter(List<String> lines, {int exitCode = 0}) {
  if (Platform.isWindows) {
    final file = File('${tmp.path}\\fake_flutter.bat')
      ..writeAsStringSync(['@echo off', for (final l in lines) 'echo $l', 'exit /b $exitCode', ''].join('\r\n'));
    return file.path;
  }
  final file = File('${tmp.path}/fake_flutter')
    ..writeAsStringSync(['#!/bin/sh', for (final l in lines) "printf '%s\\n' '$l'", 'exit $exitCode', ''].join('\n'));
  Process.runSync('chmod', ['+x', file.path]);
  return file.path;
}

/// Runs `bin/tidy_log.dart` in [tmp] with the Dart SDK of the Flutter SDK running these tests.
Future<ProcessResult> _runCli(List<String> args, {Map<String, String> env = const {}}) {
  final root = Platform.environment['FLUTTER_ROOT'];
  final sep = Platform.pathSeparator;
  final dart = root == null ? 'dart' : '$root${sep}bin${sep}dart${Platform.isWindows ? '.bat' : ''}';
  return Process.run(
    dart,
    [File('bin/tidy_log.dart').absolute.path, ...args],
    workingDirectory: tmp.path,
    environment: env,
    runInShell: Platform.isWindows,
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
  );
}
