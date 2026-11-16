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

List<Map<String, Object?>> configs(String text) =>
    [for (final c in (jsonDecode(stripJsonc(text)) as Map)['configurations'] as List) (c as Map).cast<String, Object?>()];

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
      expect(configs(edit.text).map((c) => c['name']), ['dev', 'attach', 'Chrome', 'dev (tidy logs)', 'attach (tidy logs)']);
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
    });
  });

  group('removeTidyTwins', () {
    test('restores the original file exactly', () {
      final added = addTidyTwins(_withFlavors).text;
      final removed = removeTidyTwins(added);
      expect(removed.removed, ['dev (tidy logs)', 'attach (tidy logs)']);
      expect(removed.text, _withFlavors);
    });

    test('removes a tidy config that is first or alone', () {
      const first =
          '{"configurations": [{"name": "t", "customTool": "\${workspaceFolder}/.vscode/tidy_flutter"}, {"name": "a"}]}';
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

  test('stripJsonc keeps // inside strings and drops trailing commas', () {
    expect(jsonDecode(stripJsonc('{"u": "https://x//y", /* c */ "a": [1, 2,], // d\n}')), {
      'u': 'https://x//y',
      'a': [1, 2],
    });
  });
}
