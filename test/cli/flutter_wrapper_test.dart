import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tidy_log/src/cli/flutter_wrapper.dart';
import 'package:tidy_log/src/cli/sdk_shim.dart' show shimMarker;

final _exe = Platform.isWindows ? 'flutter.bat' : 'flutter';
final _pathSep = Platform.isWindows ? ';' : ':';

void main() {
  group('findFlutter', () {
    late Directory tmp;
    late String realRoot;
    late String shimRoot;

    String makeSdk(String name) {
      final root = '${tmp.path}/$name';
      Directory('$root/bin').createSync(recursive: true);
      File('$root/bin/$_exe').writeAsStringSync('real flutter\n');
      return root;
    }

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('tidy_find_flutter_');
      realRoot = makeSdk('real_sdk');
      shimRoot = makeSdk('shim_sdk');
      File('$shimRoot/$shimMarker').writeAsStringSync('$realRoot\n');
    });

    tearDown(() => tmp.deleteSync(recursive: true));

    test('a shim first on PATH resolves to the real SDK recorded in its marker', () {
      final found = findFlutter(environment: {'PATH': '$shimRoot/bin$_pathSep/nowhere'});

      expect(found, '$realRoot/bin/$_exe');
    });

    test('FLUTTER_ROOT pointing at a shim resolves to the real SDK', () {
      expect(findFlutter(environment: {'FLUTTER_ROOT': shimRoot}), '$realRoot/bin/$_exe');
    });

    test('TIDY_FLUTTER_BIN pointing at a shim resolves to the real SDK', () {
      expect(findFlutter(environment: {'TIDY_FLUTTER_BIN': '$shimRoot/bin/$_exe'}), '$realRoot/bin/$_exe');
    });

    test('a shim whose recorded SDK is gone is skipped, and the next PATH entry is used', () {
      File('$shimRoot/$shimMarker').writeAsStringSync('${tmp.path}/deleted_sdk\n');
      final other = makeSdk('other_sdk');

      final found = findFlutter(environment: {'PATH': '$shimRoot/bin$_pathSep$other/bin'});

      expect(found, '$other/bin/$_exe');
    });

    test('a shim whose marker points at another shim is skipped', () {
      File('$shimRoot/$shimMarker').writeAsStringSync('$shimRoot\n');

      expect(findFlutter(environment: {'PATH': '$shimRoot/bin', 'FLUTTER_ROOT': shimRoot}), isNull);
    });

    test('a plain SDK is returned as given', () {
      expect(findFlutter(environment: {'FLUTTER_ROOT': realRoot}), '$realRoot/bin/$_exe');
      expect(findFlutter(environment: {'PATH': '/nowhere$_pathSep$realRoot/bin'}), '$realRoot/bin/$_exe');
    });

    test('a symlink on PATH to the shim flutter resolves to the real SDK', () {
      Directory('${tmp.path}/links').createSync();
      Link('${tmp.path}/links/$_exe').createSync('$shimRoot/bin/$_exe');

      expect(findFlutter(environment: {'PATH': '${tmp.path}/links'}), '$realRoot/bin/$_exe');
    }, skip: Platform.isWindows ? 'file symlinks need extra rights on Windows' : null);
  });

  group('usesRawKeys', () {
    test('a terminal run or attach gets single-key input', () {
      expect(usesRawKeys(['run', '-d', 'emulator-5554'], hasTerminal: true), isTrue);
      expect(usesRawKeys(['attach'], hasTerminal: true), isTrue);
      expect(usesRawKeys(['-v', 'run'], hasTerminal: true), isTrue);
    });

    test('IDE runs with --machine keep line input', () {
      expect(usesRawKeys(['run', '--machine', '-d', 'emulator-5554'], hasTerminal: true), isFalse);
      expect(usesRawKeys(['run', '--machine'], hasTerminal: false), isFalse);
    });

    test('without a terminal the input is left alone', () {
      expect(usesRawKeys(['run', '-d', 'emulator-5554'], hasTerminal: false), isFalse);
    });

    test('other commands keep line input so their prompts still work', () {
      expect(usesRawKeys(['pub', 'publish'], hasTerminal: true), isFalse);
      expect(usesRawKeys(['doctor'], hasTerminal: true), isFalse);
      expect(usesRawKeys([], hasTerminal: true), isFalse);
    });
  });
}
