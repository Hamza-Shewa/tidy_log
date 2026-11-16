import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tidy_log/src/cli/launchers.dart';

late Directory tmp;

/// A fake Flutter SDK at [name] whose `flutter` and `dart` print [label] and how they were called.
String fakeSdk(String name, String label) {
  final root = '${tmp.path}/$name';
  Directory('$root/bin').createSync(recursive: true);
  for (final tool in ['flutter', 'dart']) {
    File('$root/bin/$tool').writeAsStringSync('#!/bin/sh\necho "$label ${tool.toUpperCase()} \$*"\n');
    Process.runSync('chmod', ['+x', '$root/bin/$tool']);
  }
  return Directory(root).resolveSymbolicLinksSync();
}

/// Writes `.dart_tool/package_config.json` under [dir], listing [package].
void packageConfig(String dir, String package) {
  File('$dir/.dart_tool/package_config.json')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync('{\n  "packages": [\n    {\n      "name": "$package",\n      "rootUri": "x"\n    }\n  ]\n}\n');
}

/// Runs the shell launcher in [cwd] with only [env] (plus a minimal PATH) set.
ProcessResult launch(String cwd, List<String> args, {Map<String, String> env = const {}, String? extraPath}) {
  final script = File('${tmp.path}/tidy_flutter')..writeAsStringSync(shellLauncher);
  Process.runSync('chmod', ['+x', script.path]);
  return Process.runSync(
    script.path,
    args,
    workingDirectory: cwd,
    includeParentEnvironment: false,
    environment: {
      'PATH': [?extraPath, '/usr/bin', '/bin'].join(':'),
      ...env,
    },
  );
}

String app(String relative) => (Directory('${tmp.path}/$relative')..createSync(recursive: true)).path;

void main() {
  setUp(() => tmp = Directory(Directory.systemTemp.createTempSync('tidy_launch_').resolveSymbolicLinksSync()));
  tearDown(() => tmp.deleteSync(recursive: true));

  group('shell launcher', () {
    test('a pub workspace member uses the package config at the workspace root', () {
      final sdk = fakeSdk('sdk', 'A');
      packageConfig(app('ws'), 'tidy_log');
      final member = app('ws/packages/app');

      final result = launch(member, ['run', '-d', 'x'], env: {'FLUTTER_ROOT': sdk});

      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(result.stdout.toString().trim(), 'A DART run tidy_log run -d x');
      expect(result.stderr.toString(), isNot(contains('not resolved')));
    });

    test('the nearest package config wins, so a nested app without tidy_log falls back', () {
      final sdk = fakeSdk('sdk', 'A');
      packageConfig(app('ws'), 'tidy_log');
      final member = app('ws/packages/app');
      packageConfig(member, 'dio');

      final result = launch(member, ['run'], env: {'FLUTTER_ROOT': sdk});

      expect(result.stdout.toString().trim(), 'A FLUTTER run');
      expect(result.stderr.toString(), contains('tidy_log is not resolved yet'));
    });

    test('with no package config anywhere up the tree it falls back to plain flutter', () {
      final sdk = fakeSdk('sdk', 'A');

      final result = launch(app('lonely'), ['run'], env: {'FLUTTER_ROOT': sdk});

      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(result.stdout.toString().trim(), 'A FLUTTER run');
    });

    test('without FLUTTER_ROOT it uses the fvm SDK in the app folder before flutter on PATH', () {
      final fvm = fakeSdk('fvm_versions/3.47.5', 'FVM');
      final onPath = fakeSdk('path_sdk', 'PATH');
      final dir = app('fvm_app');
      packageConfig(dir, 'tidy_log');
      Directory('$dir/.fvm').createSync();
      Link('$dir/.fvm/flutter_sdk').createSync(fvm);

      final result = launch(dir, ['run'], extraPath: '$onPath/bin');

      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(result.stdout.toString().trim(), 'FVM DART run tidy_log run');
    });

    test('FLUTTER_ROOT wins over the fvm SDK', () {
      final fvm = fakeSdk('fvm_sdk', 'FVM');
      final root = fakeSdk('root_sdk', 'ROOT');
      final dir = app('fvm_app');
      packageConfig(dir, 'tidy_log');
      Directory('$dir/.fvm').createSync();
      Link('$dir/.fvm/flutter_sdk').createSync(fvm);

      final result = launch(dir, ['run'], env: {'FLUTTER_ROOT': root});

      expect(result.stdout.toString().trim(), 'ROOT DART run tidy_log run');
    });

    test('an .fvm folder without an SDK in it is skipped in favour of flutter on PATH', () {
      final onPath = fakeSdk('path_sdk', 'PATH');
      final dir = app('fvm_app');
      packageConfig(dir, 'tidy_log');
      Directory('$dir/.fvm/flutter_sdk').createSync(recursive: true);

      final result = launch(dir, ['run'], extraPath: '$onPath/bin');

      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(result.stdout.toString().trim(), 'PATH DART run tidy_log run');
    });

    test('with no FLUTTER_ROOT, no fvm SDK and no flutter on PATH it fails with 127', () {
      final result = launch(app('nothing'), ['run']);

      expect(result.exitCode, 127);
      expect(result.stderr.toString().trim(), 'tidy_log: flutter not found on PATH');
      expect(result.stdout.toString(), isEmpty);
    });
  });

  group('batch launcher', () {
    test('uses CRLF line endings throughout', () {
      expect(batchLauncher, endsWith('\r\n'));
      expect(batchLauncher.replaceAll('\r\n', ''), isNot(contains('\n')), reason: 'bare LF line ending');
      expect(batchLauncher.replaceAll('\r\n', ''), isNot(contains('\r')), reason: 'bare CR');
    });

    test('looks for the SDK in FLUTTER_ROOT, then .fvm, then PATH, and fails with 127 when none is found', () {
      final lines = batchLauncher.split('\r\n');
      // Whole lines, so a step that is commented out or reworded is caught.
      final steps = [
        'set "TIDY_ROOT="',
        'if defined FLUTTER_ROOT set "TIDY_ROOT=%FLUTTER_ROOT%"',
        r'if not defined TIDY_ROOT if exist ".fvm\flutter_sdk\bin\flutter.bat" set "TIDY_ROOT=%CD%\.fvm\flutter_sdk"',
        r'if not defined TIDY_ROOT for %%i in (flutter.bat) do if not "%%~$PATH:i"=="" set "TIDY_ROOT=%%~dp$PATH:i.."',
        'if defined TIDY_ROOT goto find_root_done',
        'echo tidy_log: flutter not found on PATH 1>&2',
        'exit /b 127',
        ':find_root_done',
      ];
      final start = lines.indexOf(steps.first);
      expect(start, greaterThan(0), reason: lines.join('\n'));
      expect(lines.sublist(start, start + steps.length), steps);
    });

    test('walks up to the nearest package config instead of reading only the current folder', () {
      expect(batchLauncher, isNot(contains(r'".dart_tool\package_config.json"')));
      expect(batchLauncher, contains(r'"%TIDY_DIR%\.dart_tool\package_config.json"'));
      expect(batchLauncher, contains(r'for %%d in ("%TIDY_DIR%\..") do set "TIDY_UP=%%~fd"'));
    });
  });
}
