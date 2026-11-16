@TestOn('windows')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tidy_log/src/cli/sdk_shim.dart';

late Directory tmp;

/// Paths with characters cmd.exe treats specially.
const _odd = '100% & co';

/// A fake Windows Flutter SDK whose `flutter.bat` and `dart.bat` print how they were called.
String fakeSdk() {
  final root = '${tmp.path}\\real sdk $_odd';
  for (final dir in [r'bin\cache\dart-sdk', r'bin\internal', r'packages\flutter']) {
    Directory('$root\\$dir').createSync(recursive: true);
  }
  File('$root\\version').writeAsStringSync('3.47.5\n');
  File('$root\\bin\\cache\\dart-sdk\\version').writeAsStringSync('3.13.7\n');
  File('$root\\bin\\internal\\engine.version').writeAsStringSync('abc\n');
  File('$root\\packages\\flutter\\pubspec.yaml').writeAsStringSync('name: flutter\n');
  for (final (name, label) in [('flutter', 'REAL_FLUTTER'), ('dart', 'REAL_DART')]) {
    // `set` prints the variables without cmd parsing their values.
    File('$root\\bin\\$name.bat').writeAsStringSync(
      '@echo off\r\necho $label %*\r\nset FLUTTER_ROOT\r\nset TIDY_FLUTTER_BIN 2>nul\r\nexit /b 0\r\n',
    );
  }
  return root;
}

/// Every file under [root], relative path → content.
Map<String, String> files(String root) => {
  for (final f in Directory(root).listSync(recursive: true).whereType<File>())
    f.path.substring(root.length + 1): f.readAsStringSync(),
};

/// Runs the shim's flutter.bat in [cwd]. Its path reaches cmd through a variable, as quotes around a path with
/// `&` in it would be stripped by `cmd /c`.
ProcessResult shimFlutter(String shim, List<String> args, {required String cwd}) => Process.runSync(
  'cmd',
  ['/d', '/c', '%TIDY_SHIM%', ...args],
  workingDirectory: cwd,
  environment: {'TIDY_SHIM': '"$shim\\bin\\flutter.bat"'},
);

void main() {
  setUp(() => tmp = Directory(Directory.systemTemp.createTempSync('tidy_shim_win_').resolveSymbolicLinksSync()));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('folders become junctions, files copies, and the real SDK is not changed', () {
    final real = fakeSdk();
    final before = files(real);
    final shim = '${tmp.path}\\shim $_odd';

    createShim(shim, real);

    final listing = Process.runSync(
      'cmd',
      ['/d', '/c', 'dir', '/AL', '%TIDY_DIR%'],
      environment: {'TIDY_DIR': '"$shim"'},
    ).stdout.toString();
    expect(listing, matches(RegExp(r'<JUNCTION>\s+packages ')), reason: listing);
    expect(File('$shim\\packages\\flutter\\pubspec.yaml').readAsStringSync(), 'name: flutter\n');
    expect(
      File('$shim\\bin\\cache\\dart-sdk\\version').existsSync(),
      isTrue,
      reason: 'IDEs look for bin/cache/dart-sdk',
    );
    expect(FileSystemEntity.isLinkSync('$shim\\version'), isFalse);
    expect(File('$shim\\version').readAsStringSync(), '3.47.5\n');
    expect(File('$shim\\$shimMarker').readAsStringSync().trim(), real);
    expect(files(real), before);
  });

  test('run goes through tidy_log and other commands to the real flutter, with %, & and spaces in every path', () {
    final real = fakeSdk();
    final shim = '${tmp.path}\\shim $_odd';
    createShim(shim, real);
    final app = Directory('${tmp.path}\\app $_odd')..createSync();
    File('${app.path}\\.dart_tool\\package_config.json')
      ..parent.createSync()
      ..writeAsStringSync('{"packages": [{"name": "tidy_log", "rootUri": "x"}]}');

    final run = shimFlutter(shim, ['run', '-d', 'windows', '--dart-define=GREETING=Hello!'], cwd: app.path);
    expect(run.exitCode, 0, reason: '${run.stderr}');
    expect(run.stdout.toString().split('\r\n'), [
      'REAL_DART run tidy_log run -d windows --dart-define=GREETING=Hello!',
      'FLUTTER_ROOT=$real',
      'TIDY_FLUTTER_BIN=$real\\bin\\flutter.bat',
      '',
    ]);

    final pubGet = shimFlutter(shim, ['pub', 'get'], cwd: app.path);
    expect(pubGet.exitCode, 0, reason: '${pubGet.stderr}');
    expect(pubGet.stdout.toString(), startsWith('REAL_FLUTTER pub get\r\nFLUTTER_ROOT=$real\r\n'));
  });

  test('removing or refreshing the shim never deletes anything in the real SDK', () {
    final real = fakeSdk();
    final before = files(real);
    final shim = '${tmp.path}\\shim $_odd';

    createShim(shim, real);
    createShim(shim, real); // the refresh deletes the old shim
    expect(files(real), before);
    expect(tmp.listSync().where((e) => e.path.contains('.old-') || e.path.contains('.tmp-')), isEmpty);

    expect(removeShim(shim), isTrue);
    expect(Directory(shim).existsSync(), isFalse);
    expect(files(real), before);
  });

  test('findRealFlutterRoot sees through the shim', () {
    final real = fakeSdk();
    final shim = '${tmp.path}\\shim $_odd';
    createShim(shim, real);

    expect(findRealFlutterRoot(environment: {'FLUTTER_ROOT': shim}), real);
    expect(findRealFlutterRoot(environment: {'PATH': '$shim\\bin'}), real);
  });
}
