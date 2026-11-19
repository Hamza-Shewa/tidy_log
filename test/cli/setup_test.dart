import 'dart:convert';
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

/// Every file under [dir] (relative path with `/` separators → content).
Map<String, String> snapshot(Directory dir) => {
  for (final f in dir.listSync(recursive: true, followLinks: false).whereType<File>())
    f.path.substring(dir.path.length + 1).replaceAll(r'\', '/'): f.readAsStringSync(),
};

const _pubspec = 'name: my_app\ndev_dependencies:\n  tidy_log: ^0.1.0\n';
const _launch =
    '{\n  // mine\n  "configurations": [\n    {"name": "dev", "type": "dart", "request": "launch"}\n  ]\n}\n';

int run(Directory dir, List<String> args, StringBuffer out, [StringBuffer? err]) =>
    runSetup(args, project: dir, out: _BufferSink(out), err: _BufferSink(err ?? StringBuffer()));

final _hasGit = () {
  try {
    return Process.runSync('git', ['--version']).exitCode == 0;
  } on ProcessException {
    return false;
  }
}();

/// Whether the owner may execute [path].
bool ownerCanExecute(String path) => File(path).statSync().mode & 0x40 != 0;

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
      // Not `stat -f %Lp`: that is BSD syntax, and GNU stat on Linux reads
      // `-f` as "file system status".
      expect(
        ownerCanExecute('${dir.path}/.vscode/tidy_flutter'),
        isTrue,
        reason: 'the owner must be able to execute the launcher',
      );
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

  test(
    '--sdk with --sdk-dir creates the shim there, --sdk --remove deletes it',
    () {
      final dir = project({'pubspec.yaml': _pubspec});
      final shim = '${dir.path}/shim';
      final real = findRealFlutterRoot();
      final out = StringBuffer();

      expect(
        runSetup(['--sdk', '--sdk-dir', shim, '--flutter-root', real], project: dir, out: _BufferSink(out)),
        0,
        reason: 'flutter root: $real',
      );
      expect(File('$shim/bin/flutter').existsSync(), isTrue);
      expect(out.toString(), contains('Flutter SDK path: $shim'));
      expect(snapshot(dir).keys.where((k) => !k.startsWith('shim/')), [
        'pubspec.yaml',
      ], reason: 'the project is not touched');

      expect(runSetup(['--sdk', '--remove', '--sdk-dir', shim], project: dir, out: _BufferSink(StringBuffer())), 0);
      expect(Directory(shim).existsSync(), isFalse);
    },
    skip: Platform.isWindows ? 'links the real SDK; sdk_shim_windows_test.dart covers Windows with a fake one' : false,
  );

  test('--sdk --dry-run writes nothing, and --sdk-dir needs a value', () {
    final dir = project({'pubspec.yaml': _pubspec});
    final real = findRealFlutterRoot();
    final out = StringBuffer();

    expect(
      runSetup(
        ['--sdk', '--dry-run', '--sdk-dir', '${dir.path}/shim', '--flutter-root', real],
        project: dir,
        out: _BufferSink(out),
      ),
      0,
    );
    expect(out.toString(), contains('would create ${dir.path}/shim'));
    expect(Directory('${dir.path}/shim').existsSync(), isFalse);
    expect(run(dir, ['--sdk', '--sdk-dir'], StringBuffer()), 64);
  });

  test('an unparseable launch.json is left untouched, but the launchers are written for the manual config', () {
    const broken = '{\n  "configurations": [\n    {"name": "dev", "type": "dart"\n';
    final dir = project({'pubspec.yaml': _pubspec, '.vscode/launch.json': broken});
    final err = StringBuffer();

    expect(run(dir, [], StringBuffer(), err), 1);

    final files = snapshot(dir);
    expect(files['.vscode/launch.json'], broken);
    expect(files['.vscode/tidy_flutter'], shellLauncher);
    expect(files['.vscode/tidy_flutter.bat'], batchLauncher);
    expect(err.toString(), startsWith('tidy_log setup: '));
    expect(err.toString(), contains('left .vscode/launch.json untouched'));
    expect(err.toString(), contains(r'"customTool": "${workspaceFolder}/.vscode/tidy_flutter"'));
  });

  test('a launch.json that only the JSON decoder rejects gives the friendly message, not a stack trace', () {
    const badEscape = r'{"\q": 1, "configurations": []}';
    final dir = project({'pubspec.yaml': _pubspec, '.vscode/launch.json': badEscape});
    final err = StringBuffer();

    expect(run(dir, [], StringBuffer(), err), 1);

    expect(err.toString(), startsWith('tidy_log setup: '));
    expect(err.toString(), contains('left .vscode/launch.json untouched'));
    expect(snapshot(dir)['.vscode/launch.json'], badEscape);
    expect(snapshot(dir)['.vscode/tidy_flutter'], shellLauncher);
  });

  test('a launch.json that is not UTF-8 gives the friendly message, not a stack trace', () {
    final dir = project({'pubspec.yaml': _pubspec});
    final bytes = [...utf8.encode('{"configurations": [], "x": "'), 0xFF, ...utf8.encode('"}\n')];
    final launch = File('${dir.path}/.vscode/launch.json')
      ..parent.createSync()
      ..writeAsBytesSync(bytes);
    final err = StringBuffer();

    expect(run(dir, [], StringBuffer(), err), 1);

    expect(err.toString(), startsWith('tidy_log setup: '));
    expect(err.toString(), contains('left .vscode/launch.json untouched'));
    expect(launch.readAsBytesSync(), bytes);
    expect(File('${dir.path}/.vscode/tidy_flutter').readAsStringSync(), shellLauncher);
  });

  test('a broken pubspec.yaml gives the friendly message, not a stack trace, and writes nothing', () {
    final dir = project({'pubspec.yaml': 'name: [my_app\n'});
    final err = StringBuffer();

    expect(run(dir, [], StringBuffer(), err), 1);

    expect(err.toString(), startsWith('tidy_log setup: '));
    expect(err.toString(), contains('pubspec.yaml'));
    expect(snapshot(dir).keys, ['pubspec.yaml']);
  });

  test('an edited launcher is kept on rerun and on --remove, with a note', () {
    final dir = project({'pubspec.yaml': _pubspec});
    expect(run(dir, [], StringBuffer()), 0);
    const edited = '$shellLauncher# team tweak\n';
    File('${dir.path}/.vscode/tidy_flutter').writeAsStringSync(edited);

    final rerun = StringBuffer();
    expect(run(dir, [], rerun), 0);
    expect(snapshot(dir)['.vscode/tidy_flutter'], edited);
    expect(rerun.toString(), contains('kept .vscode/tidy_flutter (it differs from the template'));
    expect(rerun.toString(), isNot(contains('kept .vscode/tidy_flutter.bat')));

    final removal = StringBuffer();
    expect(run(dir, ['--remove'], removal), 0);
    final files = snapshot(dir);
    expect(files['.vscode/tidy_flutter'], edited);
    expect(files.containsKey('.vscode/tidy_flutter.bat'), isFalse, reason: 'the unedited launcher is removed');
    expect(removal.toString(), contains('kept .vscode/tidy_flutter (it differs from the template'));
  });

  test('a launcher that lost its exec bit gets it back', () {
    final dir = project({'pubspec.yaml': _pubspec});
    expect(run(dir, [], StringBuffer()), 0);
    final launcher = '${dir.path}/.vscode/tidy_flutter';
    Process.runSync('chmod', ['-x', launcher]);
    expect(ownerCanExecute(launcher), isFalse);

    final out = StringBuffer();
    expect(run(dir, [], out), 0);

    expect(ownerCanExecute(launcher), isTrue);
    expect(out.toString(), contains('make executable .vscode/tidy_flutter'));
    expect(out.toString(), isNot(contains('Already set up')));
  }, skip: Platform.isWindows ? 'no exec bit on Windows' : false);

  test('a UTF-8 BOM at the start of launch.json is kept', () {
    final dir = project({'pubspec.yaml': _pubspec});
    final launch = File('${dir.path}/.vscode/launch.json')
      ..parent.createSync()
      ..writeAsBytesSync([0xEF, 0xBB, 0xBF, ...utf8.encode(_launch)]);

    expect(run(dir, [], StringBuffer()), 0);

    final bytes = launch.readAsBytesSync();
    expect(bytes.take(3), [0xEF, 0xBB, 0xBF]);
    expect(utf8.decode(bytes.skip(3).toList()), startsWith('{\n  // mine'), reason: 'exactly one BOM');
    expect(utf8.decode(bytes.skip(3).toList()), contains('"name": "dev (tidy logs)"'));
  });

  test('setup then --remove on a project without .vscode leaves no .vscode', () {
    final dir = project({'pubspec.yaml': _pubspec});

    expect(run(dir, [], StringBuffer()), 0);
    expect(run(dir, ['--remove'], StringBuffer()), 0);

    expect(snapshot(dir).keys, ['pubspec.yaml']);
    expect(Directory('${dir.path}/.vscode').existsSync(), isFalse);
  });

  test('setup then --remove keeps a .vscode folder that has other files', () {
    final dir = project({'pubspec.yaml': _pubspec, '.vscode/settings.json': '{}\n'});
    final before = snapshot(dir);

    expect(run(dir, [], StringBuffer()), 0);
    expect(run(dir, ['--remove'], StringBuffer()), 0);

    expect(snapshot(dir), before);
  });

  test('--remove keeps a tidy config the team edited, and the launchers it uses, with notes', () {
    final dir = project({'pubspec.yaml': _pubspec, '.vscode/launch.json': _launch});
    expect(run(dir, [], StringBuffer()), 0);
    final launch = File('${dir.path}/.vscode/launch.json');
    launch.writeAsStringSync(
      launch.readAsStringSync().replaceFirst(
        '"name": "dev (tidy logs)",',
        '"name": "dev (tidy logs)", "deviceId": "x",',
      ),
    );

    final out = StringBuffer();
    expect(run(dir, ['--remove'], out), 0);

    final files = snapshot(dir);
    expect(files['.vscode/launch.json'], contains('"deviceId": "x"'));
    expect(files['.vscode/tidy_flutter'], shellLauncher);
    expect(files['.vscode/tidy_flutter.bat'], batchLauncher);
    expect(out.toString(), contains('left as is: dev (tidy logs): changed since setup added it'));
    expect(out.toString(), contains('kept .vscode/tidy_flutter (launch config "dev (tidy logs)" still uses it)'));
  });

  test('a launcher from an earlier version is updated on rerun, and removed by --remove', () {
    final old = previousBatchLaunchers.single;
    final dir = project({'pubspec.yaml': _pubspec, '.vscode/tidy_flutter.bat': old});

    final out = StringBuffer();
    expect(run(dir, [], out), 0);
    expect(snapshot(dir)['.vscode/tidy_flutter.bat'], batchLauncher);
    expect(out.toString(), contains('updated .vscode/tidy_flutter.bat from an earlier version'));

    File('${dir.path}/.vscode/tidy_flutter.bat').writeAsStringSync(old);
    expect(run(dir, ['--remove'], StringBuffer()), 0);
    expect(snapshot(dir).keys, ['pubspec.yaml']);
  });

  group('in a git work tree', () {
    String git(Directory dir, List<String> args) {
      final result = Process.runSync('git', args, workingDirectory: dir.path);
      expect(result.exitCode, 0, reason: 'git ${args.join(' ')}: ${result.stderr}');
      return '${result.stdout}'.trim();
    }

    Directory repo(Map<String, String> files) {
      final dir = project(files);
      git(dir, ['init', '-q']);
      // As on Windows, where git cannot see executable bits.
      git(dir, ['config', 'core.fileMode', 'false']);
      return dir;
    }

    test('an untracked launcher gets the command that marks it executable, and a .gitattributes note', () {
      final dir = repo({'pubspec.yaml': _pubspec});
      final out = StringBuffer();

      expect(run(dir, [], out), 0);

      expect(out.toString(), contains('git update-index --chmod=+x .vscode/tidy_flutter'));
      expect(out.toString(), contains('`*.bat text eol=crlf`'));
      expect(File('${dir.path}/.gitattributes').existsSync(), isFalse, reason: 'never edited');
    });

    test('a launcher git already tracks gets its executable bit in the index', () {
      final dir = repo({'pubspec.yaml': _pubspec, '.gitattributes': '*.bat text eol=crlf\n'});
      expect(run(dir, [], StringBuffer()), 0);
      git(dir, ['add', '.vscode']);
      expect(git(dir, ['ls-files', '-s', '.vscode/tidy_flutter']), startsWith('100644'));
      File('${dir.path}/.vscode/tidy_flutter').deleteSync();

      final out = StringBuffer();
      expect(run(dir, [], out), 0);

      expect(git(dir, ['ls-files', '-s', '.vscode/tidy_flutter']), startsWith('100755'));
      expect(out.toString(), contains('set the executable bit of .vscode/tidy_flutter in git'));
      expect(out.toString(), isNot(contains('eol=crlf')), reason: '.gitattributes already has the rule');
    });
  }, skip: _hasGit ? false : 'git is not installed');

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
