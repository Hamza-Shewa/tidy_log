import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tidy_log/src/cli/launchers.dart';
import 'package:tidy_log/src/cli/sdk_shim.dart';
import 'package:tidy_log/src/cli/setup.dart';

/// A throwaway project folder with the given files.
Directory project(Map<String, String> files) {
  final dir = Directory.systemTemp.createTempSync('tidy_setup_');
  addTearDown(() => dir.deleteSync(recursive: true));
  for (final MapEntry(:key, :value) in files.entries) {
    File('${dir.path}/$key')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(value);
  }
  return dir;
}

/// Every file under [dir] (relative path → content).
Map<String, String> snapshot(Directory dir) => {
  for (final f in dir.listSync(recursive: true, followLinks: false).whereType<File>())
    f.path.substring(dir.path.length + 1): f.readAsStringSync(),
};

const _pubspec = 'name: my_app\ndev_dependencies:\n  tidy_log: ^0.1.0\n';
const _launch = '{\n  // mine\n  "configurations": [\n    {"name": "dev", "type": "dart", "request": "launch"}\n  ]\n}\n';

int run(Directory dir, List<String> args, StringBuffer out) {
  final sink = _BufferSink(out);
  return runSetup(args, project: dir, out: sink);
}

void main() {
  test('setup writes both launchers and a tidy twin, and prints the app snippet', () {
    final dir = project({'pubspec.yaml': _pubspec, '.vscode/launch.json': _launch});
    final out = StringBuffer();

    expect(run(dir, [], out), 0);

    final files = snapshot(dir);
    expect(files['.vscode/tidy_flutter'], shellLauncher);
    expect(files['.vscode/tidy_flutter.bat'], batchLauncher);
    expect(files['.vscode/launch.json'], contains('"name": "dev (tidy logs)"'));
    expect(files['.vscode/launch.json'], contains('// mine'));
    expect(out.toString(), contains("TidyLog.configure(projectPackages: ['my_app'])"));
    if (!Platform.isWindows) {
      final mode = Process.runSync('stat', ['-f', '%Lp', '${dir.path}/.vscode/tidy_flutter']).stdout.toString().trim();
      expect(int.parse(mode[0]) & 1, 1, reason: 'the owner must be able to execute the launcher (mode $mode)');
    }
  });

  test('setup then --remove gives back the project exactly as it was', () {
    final dir = project({'pubspec.yaml': _pubspec, '.vscode/launch.json': _launch});
    final before = snapshot(dir);

    expect(run(dir, [], StringBuffer()), 0);
    expect(run(dir, ['--remove'], StringBuffer()), 0);

    expect(snapshot(dir), before);
  });

  test('a second setup changes nothing', () {
    final dir = project({'pubspec.yaml': _pubspec});
    run(dir, [], StringBuffer());
    final after = snapshot(dir);
    final out = StringBuffer();

    expect(run(dir, [], out), 0);
    expect(out.toString(), contains('Already set up'));
    expect(snapshot(dir), after);
  });

  test('--dry-run reports the changes and writes nothing', () {
    final dir = project({'pubspec.yaml': _pubspec});
    final out = StringBuffer();

    expect(run(dir, ['--dry-run'], out), 0);
    expect(out.toString(), contains('would write  .vscode/launch.json'));
    expect(snapshot(dir).keys, ['pubspec.yaml']);
  });

  test('refuses a project that does not depend on tidy_log, and writes nothing', () {
    final dir = project({'pubspec.yaml': 'name: other\ndependencies:\n  dio: any\n'});
    expect(run(dir, [], StringBuffer()), 1);
    expect(snapshot(dir).keys, ['pubspec.yaml']);
  });

  test('the shell launcher falls back to plain flutter before pub get', () {
    final dir = project({'pubspec.yaml': _pubspec});
    run(dir, [], StringBuffer());

    // No .dart_tool/package_config.json yet, as in a fresh clone.
    final result = Process.runSync('${dir.path}/.vscode/tidy_flutter', ['--version'], workingDirectory: dir.path);

    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(result.stdout.toString(), startsWith('Flutter '));
    expect(result.stderr.toString(), contains('tidy_log is not resolved yet'));
  }, skip: Platform.isWindows ? 'the shell launcher is for macOS and Linux' : false);

  test('--sdk with --sdk-dir creates the shim there, --sdk --remove deletes it', () {
    final dir = project({'pubspec.yaml': _pubspec});
    final shim = '${dir.path}/shim';
    final real = findRealFlutterRoot();
    final out = StringBuffer();

    expect(runSetup(['--sdk', '--sdk-dir', shim, '--flutter-root', real], project: dir, out: _BufferSink(out)), 0,
        reason: 'flutter root: $real');
    expect(File('$shim/bin/flutter').existsSync(), isTrue);
    expect(out.toString(), contains('Flutter SDK path: $shim'));
    expect(snapshot(dir).keys.where((k) => !k.startsWith('shim/')), ['pubspec.yaml'], reason: 'the project is not touched');

    expect(runSetup(['--sdk', '--remove', '--sdk-dir', shim], project: dir, out: _BufferSink(StringBuffer())), 0);
    expect(Directory(shim).existsSync(), isFalse);
  }, skip: Platform.isWindows ? 'the shim test uses symlinks' : false);

  test('--sdk --dry-run writes nothing, and --sdk-dir needs a value', () {
    final dir = project({'pubspec.yaml': _pubspec});
    final real = findRealFlutterRoot();
    final out = StringBuffer();

    expect(runSetup(['--sdk', '--dry-run', '--sdk-dir', '${dir.path}/shim', '--flutter-root', real], project: dir, out: _BufferSink(out)), 0);
    expect(out.toString(), contains('would create ${dir.path}/shim'));
    expect(Directory('${dir.path}/shim').existsSync(), isFalse);
    expect(run(dir, ['--sdk', '--sdk-dir'], StringBuffer()), 64);
  });

  test('an unknown option is a usage error', () {
    final dir = project({'pubspec.yaml': _pubspec});
    expect(run(dir, ['--sdkk'], StringBuffer()), 64);
  });
}

/// Collects what setup prints.
final class _BufferSink implements IOSink {
  _BufferSink(this.buffer);
  final StringBuffer buffer;
  @override
  void writeln([Object? object = '']) => buffer.writeln(object);
  @override
  void write(Object? object) => buffer.write(object);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
