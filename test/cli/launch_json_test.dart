import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tidy_log/src/cli/launch_json.dart';

/// A launch.json as people write it: comments, a trailing comma, flavors,
/// and a `//` inside a string that must not be taken for a comment.
const _withFlavors = '''
{
  // Flavors
  "version": "0.2.0",
  "configurations": [
    {
      "name": "dev", // the usual one
      "type": "dart",
      "request": "launch",
      "program": "lib/main_dev.dart",
      "args": ["--flavor", "dev", "--dart-define=URL=https://dev.example.test"],
    },
    /* attach to a running app */
    {
      "name": "attach",
      "type": "dart",
      "request": "attach",
    },
    {
      "name": "Chrome",
      "type": "chrome",
      "request": "launch",
    },
  ],
}
''';

/// The twin setup writes for `{"name": "a", "type": "dart"}`.
const _twinOfA =
    '{"name": "a (tidy logs)", "type": "dart", "customTool": "\${workspaceFolder}/.vscode/tidy_flutter", '
    '"customToolReplacesArgs": 0, "windows": {"customTool": "\${workspaceFolder}\\\\.vscode\\\\tidy_flutter.bat"}}';

List<Map<String, Object?>> configs(String text) => [
  for (final c in (jsonDecode(stripJsonc(text)) as Map)['configurations'] as List) (c as Map).cast<String, Object?>(),
];

void main() {
  group('addTidyTwins', () {
    test('a missing launch.json becomes one tidy config', () {
      final edit = addTidyTwins(null);
      expect(edit.added, ['Flutter (tidy logs)']);
      final only = configs(edit.text).single;
      expect(only['program'], 'lib/main.dart');
      expect(only['customTool'], r'${workspaceFolder}/.vscode/tidy_flutter');
      expect(only['customToolReplacesArgs'], 0);
      expect((only['windows']! as Map)['customTool'], r'${workspaceFolder}\.vscode\tidy_flutter.bat');
    });

    test('adds a twin of every Dart config and keeps their fields', () {
      final edit = addTidyTwins(_withFlavors);
      expect(edit.added, ['dev (tidy logs)', 'attach (tidy logs)']);
      final dev = configs(edit.text).firstWhere((c) => c['name'] == 'dev (tidy logs)');
      expect(dev['program'], 'lib/main_dev.dart');
      expect(dev['args'], ['--flavor', 'dev', '--dart-define=URL=https://dev.example.test']);
      expect(dev['customTool'], r'${workspaceFolder}/.vscode/tidy_flutter');
      expect(configs(edit.text).map((c) => c['name']), [
        'dev',
        'attach',
        'Chrome',
        'dev (tidy logs)',
        'attach (tidy logs)',
      ]);
    });

    test('the original text is kept byte for byte, comments included', () {
      final edit = addTidyTwins(_withFlavors);
      final insertAt = _withFlavors.lastIndexOf('}', _withFlavors.lastIndexOf(']')) + 2; // after "},"
      expect(edit.text.substring(0, insertAt), _withFlavors.substring(0, insertAt));
      expect(edit.text, endsWith(_withFlavors.substring(insertAt)));
      expect(edit.text, contains('// the usual one'));
      expect(edit.text, contains('/* attach to a running app */'));
    });

    test('running it again changes nothing', () {
      final once = addTidyTwins(_withFlavors).text;
      final twice = addTidyTwins(once);
      expect(twice.changed, isFalse);
      expect(twice.text, once);
    });

    test('a config with its own customTool is left alone and reported', () {
      const fvm = '{"configurations": [{"name": "fvm", "type": "dart", "request": "launch", "customTool": "fvm"}]}';
      final edit = addTidyTwins(fvm);
      expect(edit.skipped.single, startsWith('fvm: already uses customTool fvm'));
      expect(edit.added, ['Flutter (tidy logs)'], reason: 'they still get one tidy config');
    });

    test('works without a trailing comma and in an empty list', () {
      final plain = addTidyTwins('{"configurations": [{"name": "a", "type": "dart", "request": "launch"}]}');
      expect(configs(plain.text).map((c) => c['name']), ['a', 'a (tidy logs)']);
      final empty = addTidyTwins('{\n  "configurations": []\n}\n');
      expect(configs(empty.text).single['name'], 'Flutter (tidy logs)');
    });

    test('a file without configurations or with broken JSON is refused', () {
      expect(() => addTidyTwins('{"version": "0.2.0"}'), throwsA(isA<LaunchJsonException>()));
      expect(() => addTidyTwins('{"configurations": [{"name": "a"'), throwsA(isA<LaunchJsonException>()));
      expect(() => addTidyTwins(r'{"\q": 1, "configurations": []}'), throwsA(isA<LaunchJsonException>()));
    });
  });

  group('file styles', () {
    test('a CRLF file stays CRLF and a rerun or remove keeps it intact', () {
      final crlf = _withFlavors.replaceAll('\n', '\r\n');
      final added = addTidyTwins(crlf).text;
      expect(added.replaceAll('\r\n', ''), isNot(contains('\n')), reason: 'no bare LF line endings');
      expect(removeTidyTwins(added).text, crlf);
    });

    test('a tab-indented file gets tab-indented twins', () {
      const tabs = '{\n\t"configurations": [\n\t\t{\n\t\t\t"name": "a",\n\t\t\t"type": "dart"\n\t\t}\n\t]\n}\n';
      final added = addTidyTwins(tabs).text;
      expect(added, contains('\t\t\t"name": "a (tidy logs)"'));
      expect(added, isNot(contains(' "name"')));
      expect(removeTidyTwins(added).text, tabs);
    });
  });

  group('removeTidyTwins', () {
    test('keeps comments next to a twin the user moved or annotated', () {
      const moved =
          '''{
  "configurations": [
    {"name": "a", "type": "dart"},
    // IMPORTANT: keep this note
    $_twinOfA,
    // about b
    {"name": "b", "type": "dart"}
  ]
}
''';
      final removed = removeTidyTwins(moved).text;
      expect(removed, contains('// IMPORTANT: keep this note'));
      expect(removed, contains('// about b'));
      expect(configs(removed).map((c) => c['name']), ['a', 'b']);
    });

    test('a file setup created from scratch is reported as empty after remove', () {
      final created = addTidyTwins(null).text;
      expect(removeTidyTwins(created).leftEmpty, isTrue);
      expect(removeTidyTwins(_withFlavors).leftEmpty, isFalse);
    });

    test('only configs that point exactly at the setup launcher are ours', () {
      const lookalike =
          '{"configurations": [{"name": "x", "type": "dart", "customTool": "\${workspaceFolder}/.vscode/tidy_flutter_old"}]}';
      expect(removeTidyTwins(lookalike).changed, isFalse);
    });

    test('restores the original file exactly', () {
      final added = addTidyTwins(_withFlavors).text;
      final removed = removeTidyTwins(added);
      expect(removed.removed, ['dev (tidy logs)', 'attach (tidy logs)']);
      expect(removed.text, _withFlavors);
    });

    test('removes a tidy config that is first or alone', () {
      final first = '{"configurations": [${jsonEncode(defaultTidyConfig())}, {"name": "a"}]}';
      expect(configs(removeTidyTwins(first).text).map((c) => c['name']), ['a']);
      expect(configs(removeTidyTwins(addTidyTwins(null).text).text), isEmpty);
    });

    test('never removes a hand-made config that uses another tidy_flutter path', () {
      const manual =
          '{"configurations": [{"name": "old", "type": "dart", "customTool": "\${workspaceFolder}/../build/tidy_flutter"}]}';
      expect(removeTidyTwins(manual).changed, isFalse);
      expect(addTidyTwins(manual).skipped.single, startsWith('old: already uses customTool'));
    });

    test('leaves a file without tidy configs unchanged', () {
      expect(removeTidyTwins(_withFlavors).changed, isFalse);
      expect(removeTidyTwins(_withFlavors).text, _withFlavors);
    });
  });

  group('which configs get a twin', () {
    test('test configs and plain Dart programs get none, with a note', () {
      const mixed = '''{"configurations": [
        {"name": "app", "type": "dart", "request": "launch", "program": "lib/main.dart"},
        {"name": "Flutter tests", "type": "dart", "request": "launch", "program": "test/"},
        {"name": "one test", "type": "dart", "request": "launch", "program": "\${workspaceFolder}\\\\test\\\\a_test.dart"},
        {"name": "e2e", "type": "dart", "request": "launch", "program": "integration_test/app_test.dart"},
        {"name": "template", "type": "dart", "request": "launch", "templateFor": "test"},
        {"name": "server", "type": "dart", "request": "launch", "program": "bin/server.dart"},
        {"name": "attach", "type": "dart", "request": "attach"}
      ]}''';
      final edit = addTidyTwins(mixed);
      expect(edit.added, ['app (tidy logs)', 'attach (tidy logs)']);
      expect(edit.skipped, [
        'Flutter tests: a test config (tidy_log only tidies flutter run and attach)',
        'one test: a test config (tidy_log only tidies flutter run and attach)',
        'e2e: a test config (tidy_log only tidies flutter run and attach)',
        'template: a test config (tidy_log only tidies flutter run and attach)',
        'server: not a Flutter app (program bin/server.dart)',
      ]);
    });

    test('only test configs: the project still gets one tidy config', () {
      final edit = addTidyTwins('{"configurations": [{"name": "t", "type": "dart", "program": "test/"}]}');
      expect(edit.added, ['Flutter (tidy logs)']);
    });

    test('configs with the same name get twins with distinct names, and a rerun adds nothing', () {
      const dupes = '''{"configurations": [
        {"name": "dev", "type": "dart", "args": ["--flavor", "a"]},
        {"name": "dev", "type": "dart", "args": ["--flavor", "b"]}
      ]}''';
      final edit = addTidyTwins(dupes);
      expect(edit.added, ['dev (tidy logs)', 'dev (tidy logs 2)']);
      final twins = configs(edit.text).skip(2).toList();
      expect(twins.map((c) => c['args']), [
        ['--flavor', 'a'],
        ['--flavor', 'b'],
      ]);
      expect(addTidyTwins(edit.text).changed, isFalse);

      final removed = removeTidyTwins(edit.text);
      expect(removed.removed, ['dev (tidy logs)', 'dev (tidy logs 2)']);
      expect(removed.text, dupes);
    });

    test('a windows.customTool of its own is kept, with a note', () {
      const own =
          '{"configurations": [{"name": "a", "type": "dart", "windows": {"customTool": "C:\\\\fvm\\\\flutter.bat"}}]}';
      final edit = addTidyTwins(own);
      final twin = configs(edit.text).last;
      expect(twin['customTool'], tidyToolFields['customTool']);
      expect(twin['windows'], {'customTool': r'C:\fvm\flutter.bat'});
      expect(edit.notes.single, contains(r'"a (tidy logs)" keeps its own windows.customTool (C:\fvm\flutter.bat)'));
      expect(configs(removeTidyTwins(edit.text).text), configs(own));
    });
  });

  group('--remove keeps tidy configs that were changed', () {
    test('an edited twin stays, with a note', () {
      final added = addTidyTwins(_withFlavors).text;
      final edited = added.replaceFirst(
        '"name": "attach (tidy logs)",',
        '"name": "attach (tidy logs)",\n      "deviceId": "x",',
      );
      expect(edited, isNot(added));

      final removed = removeTidyTwins(edited);
      expect(removed.removed, ['dev (tidy logs)']);
      expect(removed.kept, ['attach (tidy logs)']);
      expect(removed.skipped.single, startsWith('attach (tidy logs): changed since setup added it'));
      expect(configs(removed.text).map((c) => c['name']), ['dev', 'attach', 'Chrome', 'attach (tidy logs)']);
    });

    test('a twin written by an earlier version, which replaced windows.customTool, is still removed', () {
      const old = '''{"configurations": [
        {"name": "a", "type": "dart", "windows": {"customTool": "fvm.bat"}},
        {"name": "a (tidy logs)", "type": "dart", "customTool": "\${workspaceFolder}/.vscode/tidy_flutter", "customToolReplacesArgs": 0, "windows": {"customTool": "\${workspaceFolder}\\\\.vscode\\\\tidy_flutter.bat"}}
      ]}''';
      expect(removeTidyTwins(old).removed, ['a (tidy logs)']);
    });
  });

  test('stripJsonc keeps // inside strings and drops trailing commas', () {
    expect(jsonDecode(stripJsonc('{"u": "https://x//y", /* c */ "a": [1, 2,], // d\n}')), {
      'u': 'https://x//y',
      'a': [1, 2],
    });
  });
}
