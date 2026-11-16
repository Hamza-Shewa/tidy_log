@TestOn('mac-os || linux')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tidy_log/src/cli/sdk_shim.dart';

late Directory tmp;

/// Folders a test made unreadable; tearDown gives them back their permissions so they can be deleted.
final locked = <String>[];

/// A fake Flutter SDK whose `flutter` and `dart` print how they were called.
String fakeSdk() {
  final root = '${tmp.path}/real_sdk';
  for (final dir in ['bin/cache/dart-sdk', 'bin/internal', 'packages/flutter']) {
    Directory('$root/$dir').createSync(recursive: true);
  }
  File('$root/version').writeAsStringSync('3.47.5\n');
  for (final (name, label) in [('flutter', 'REAL_FLUTTER'), ('dart', 'REAL_DART')]) {
    File(
      '$root/bin/$name',
    ).writeAsStringSync('#!/bin/sh\necho "$label \$* | bin=\$TIDY_FLUTTER_BIN | root=\$FLUTTER_ROOT"\n');
    Process.runSync('chmod', ['+x', '$root/bin/$name']);
  }
  return Directory(root).resolveSymbolicLinksSync();
}

/// Runs the shim's flutter in [project] and returns its output.
String shimFlutter(String shim, List<String> args, {String? project, Map<String, String> env = const {}}) {
  final result = Process.runSync('$shim/bin/flutter', args, workingDirectory: project ?? tmp.path, environment: env);
  expect(result.exitCode, 0, reason: '${result.stderr}');
  return result.stdout.toString().trim();
}

/// A project folder; [withTidyLog] makes pub's package config list tidy_log.
String project({required bool withTidyLog}) {
  final dir = Directory('${tmp.path}/app_${withTidyLog ? 'tidy' : 'plain'}')..createSync();
  File('${dir.path}/.dart_tool/package_config.json')
    ..parent.createSync()
    ..writeAsStringSync('{"packages": [{"name": "${withTidyLog ? 'tidy_log' : 'dio'}", "rootUri": "x"}]}');
  return dir.path;
}

void main() {
  setUp(() => tmp = Directory.systemTemp.createTempSync('tidy_shim_'));
  tearDown(() {
    for (final path in locked) {
      Process.runSync('chmod', ['755', path]);
    }
    locked.clear();
    tmp.deleteSync(recursive: true);
  });

  test('links the real SDK and never copies or changes it', () {
    final real = fakeSdk();
    final before = File('$real/bin/flutter').readAsStringSync();
    final shim = '${tmp.path}/shim';

    createShim(shim, real);

    expect(Link('$shim/version').targetSync(), '$real/version');
    expect(Link('$shim/packages').targetSync(), '$real/packages');
    expect(Link('$shim/bin/cache').targetSync(), '$real/bin/cache', reason: 'IDEs look for bin/cache/dart-sdk');
    expect(Link('$shim/bin/dart').targetSync(), '$real/bin/dart');
    expect(FileSystemEntity.isLinkSync('$shim/bin/flutter'), isFalse, reason: 'flutter is the router script');
    expect(File('$real/bin/flutter').readAsStringSync(), before);
    expect(File('$shim/$shimMarker').readAsStringSync().trim(), real);
  });

  test('run and attach go through tidy_log only in projects that depend on it', () {
    final real = fakeSdk();
    final shim = '${tmp.path}/shim';
    createShim(shim, real);
    final tidy = project(withTidyLog: true);
    final plain = project(withTidyLog: false);

    expect(
      shimFlutter(shim, ['run', '-d', 'emulator-5554'], project: tidy),
      'REAL_DART run tidy_log run -d emulator-5554 | bin=$real/bin/flutter | root=$real',
    );
    expect(
      shimFlutter(shim, ['--no-color', 'attach'], project: tidy),
      startsWith('REAL_DART run tidy_log --no-color attach'),
    );
    expect(shimFlutter(shim, ['run', '-d', 'x'], project: plain), startsWith('REAL_FLUTTER run -d x'));
  });

  test('run goes through tidy_log in a pub workspace member, using the config at the workspace root', () {
    final real = fakeSdk();
    final shim = '${tmp.path}/shim';
    createShim(shim, real);
    final root = Directory('${tmp.path}/ws')..createSync();
    File('${root.path}/.dart_tool/package_config.json')
      ..parent.createSync()
      ..writeAsStringSync('{"packages": [{"name": "tidy_log", "rootUri": "x"}]}');
    final member = (Directory('${root.path}/packages/app')..createSync(recursive: true)).path;

    expect(shimFlutter(shim, ['run'], project: member), startsWith('REAL_DART run tidy_log run |'));
    expect(shimFlutter(shim, ['pub', 'get'], project: member), startsWith('REAL_FLUTTER pub get |'));
  });

  test('the nearest package config wins over one further up', () {
    final real = fakeSdk();
    final shim = '${tmp.path}/shim';
    createShim(shim, real);
    final root = Directory('${tmp.path}/ws')..createSync();
    File('${root.path}/.dart_tool/package_config.json')
      ..parent.createSync()
      ..writeAsStringSync('{"packages": [{"name": "tidy_log", "rootUri": "x"}]}');
    final nested = Directory('${root.path}/nested')..createSync();
    File('${nested.path}/.dart_tool/package_config.json')
      ..parent.createSync()
      ..writeAsStringSync('{"packages": [{"name": "dio", "rootUri": "x"}]}');

    expect(shimFlutter(shim, ['run'], project: nested.path), startsWith('REAL_FLUTTER run |'));
  });

  test('every other command goes straight to the real flutter', () {
    final real = fakeSdk();
    final shim = '${tmp.path}/shim';
    createShim(shim, real);
    final tidy = project(withTidyLog: true);

    for (final args in [
      ['--version'],
      ['pub', 'get'],
      ['daemon'],
      ['test', 'test/run_test.dart'],
    ]) {
      expect(shimFlutter(shim, args, project: tidy), startsWith('REAL_FLUTTER ${args.join(' ')} |'));
    }
  });

  test('a call from inside the tidy_log runner never loops back through it', () {
    final real = fakeSdk();
    final shim = '${tmp.path}/shim';
    createShim(shim, real);

    final out = shimFlutter(shim, ['run'], project: project(withTidyLog: true), env: {'TIDY_LOG_WRAPPED': '1'});
    expect(out, startsWith('REAL_FLUTTER run'));
  });

  test('refreshing an existing shim works, but a folder that is not a shim is never touched', () {
    final real = fakeSdk();
    final shim = '${tmp.path}/shim';
    createShim(shim, real);
    createShim(shim, real);
    expect(File('$shim/$shimMarker').existsSync(), isTrue);

    final mine = Directory('${tmp.path}/my_stuff')..createSync();
    File('${mine.path}/keep.txt').writeAsStringSync('x');
    expect(() => createShim(mine.path, real), throwsA(isA<ShimException>()));
    expect(() => removeShim(mine.path), throwsA(isA<ShimException>()));
    expect(File('${mine.path}/keep.txt').existsSync(), isTrue);
  });

  test('a refresh that fails part-way leaves the old shim working and removable', () {
    final real = fakeSdk();
    final shim = '${tmp.path}/shim';
    createShim(shim, real);
    final before = File('$shim/bin/flutter').readAsStringSync();

    Process.runSync('chmod', ['000', '$real/bin']);
    locked.add('$real/bin');
    expect(() => createShim(shim, real), throwsA(isA<FileSystemException>()));

    expect(File('$shim/$shimMarker').readAsStringSync().trim(), real);
    expect(File('$shim/bin/flutter').readAsStringSync(), before);
    expect(Link('$shim/bin/dart').targetSync(), '$real/bin/dart');
    final leftovers = tmp.listSync().map((e) => e.uri.pathSegments.where((s) => s.isNotEmpty).last);
    expect(leftovers.where((name) => name.startsWith('shim.')), isEmpty, reason: 'temp folder must be cleaned up');

    Process.runSync('chmod', ['755', '$real/bin']);
    createShim(shim, real);
    expect(shimFlutter(shim, ['--version']), startsWith('REAL_FLUTTER --version |'));
    expect(removeShim(shim), isTrue);
    expect(Directory(shim).existsSync(), isFalse);
  });

  test('a first build that fails leaves nothing behind, so a retry works', () {
    final real = fakeSdk();
    final shim = '${tmp.path}/shim';

    Process.runSync('chmod', ['000', '$real/bin']);
    locked.add('$real/bin');
    expect(() => createShim(shim, real), throwsA(isA<FileSystemException>()));
    expect(tmp.listSync().map((e) => e.path).where((p) => p.startsWith(shim)), isEmpty);

    Process.runSync('chmod', ['755', '$real/bin']);
    createShim(shim, real);
    expect(File('$shim/$shimMarker').existsSync(), isTrue);
  });

  test('the batch shim uses CRLF line endings throughout', () {
    final bat = shimBatchScript(r'C:\flutter');
    expect(bat, endsWith('\r\n'));
    expect(bat.replaceAll('\r\n', ''), isNot(contains('\n')), reason: 'bare LF line ending');
    expect(bat.replaceAll('\r\n', ''), isNot(contains('\r')), reason: 'bare CR');
  });

  test('the batch shim never passes %* on while delayed expansion is on, so a ! in an argument survives', () {
    final lines = shimBatchScript(r'C:\flutter').split('\r\n').map((l) => l.trim()).toList();
    expect(lines.firstWhere((l) => l.startsWith('setlocal')), 'setlocal DisableDelayedExpansion');

    var delayed = false;
    final forwarding = <String>[];
    for (final line in lines) {
      if (line.toLowerCase().startsWith('setlocal enabledelayedexpansion')) delayed = true;
      if (line.toLowerCase().startsWith('endlocal')) delayed = false;
      if (line.startsWith('call ') && line.contains('%*')) {
        expect(delayed, isFalse, reason: 'runs with delayed expansion on: $line');
        forwarding.add(line);
      }
    }
    expect(forwarding, [
      'call :scan %*',
      r'call "%TIDY_REAL%\bin\dart.bat" run tidy_log %*',
      r'call "%TIDY_REAL%\bin\flutter.bat" %*',
    ]);
  });

  test('the batch shim walks up to the nearest package config', () {
    final bat = shimBatchScript(r'C:\flutter');
    expect(bat, isNot(contains(r'".dart_tool\package_config.json"')));
    expect(bat, contains(r'"%TIDY_DIR%\.dart_tool\package_config.json"'));
  });

  test('removeShim deletes only the shim', () {
    final real = fakeSdk();
    final shim = '${tmp.path}/shim';
    createShim(shim, real);

    expect(removeShim(shim), isTrue);
    expect(Directory(shim).existsSync(), isFalse);
    expect(File('$real/bin/flutter').existsSync(), isTrue);
    expect(removeShim(shim), isFalse);
  });

  test('findRealFlutterRoot sees through a shim to the real SDK', () {
    final real = fakeSdk();
    final shim = '${tmp.path}/shim';
    createShim(shim, real);

    expect(findRealFlutterRoot(environment: {'FLUTTER_ROOT': shim}), real);
    expect(findRealFlutterRoot(environment: {'PATH': '$shim/bin'}), real);
    expect(findRealFlutterRoot(explicit: real, environment: const {}), real);
    expect(() => findRealFlutterRoot(explicit: tmp.path, environment: const {}), throwsA(isA<ShimException>()));
    expect(() => findRealFlutterRoot(environment: const {}), throwsA(isA<ShimException>()));
  });
}
