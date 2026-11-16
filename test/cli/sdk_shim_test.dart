@TestOn('mac-os || linux')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tidy_log/src/cli/sdk_shim.dart';

late Directory tmp;

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
  tearDown(() => tmp.deleteSync(recursive: true));

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
