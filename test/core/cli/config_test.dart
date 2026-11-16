import 'package:flutter_test/flutter_test.dart';
import 'package:tidy_log/src/core.dart';

/// The problems [yaml] is rejected with, one per line.
List<String> problems(String yaml) {
  try {
    TidyConfig.fromYaml(yaml);
  } on FormatException catch (e) {
    return e.message.split('\n');
  }
  fail('accepted: $yaml');
}

void main() {
  group('tidy_log.yaml checks', () {
    test('a value of the wrong type names the key', () {
      expect(problems('hide_tags: FlutterGeolocator\n'), ['tidy_log.yaml: hide_tags: expected a list of strings']);
      expect(problems('max_width: "120"\n'), [
        'tidy_log.yaml: max_width: expected a whole number above 0, such as 120',
      ]);
      expect(problems('max_width: 0\n'), ['tidy_log.yaml: max_width: expected a whole number above 0, such as 120']);
      expect(problems('color: "no"\n'), ['tidy_log.yaml: color: expected true or false']);
      expect(problems('preset: loud\n'), ['tidy_log.yaml: preset: expected one of quiet, all']);
      expect(problems('min_native_level: loud\n'), [
        'tidy_log.yaml: min_native_level: expected one of verbose, debug, info, warning, error, fatal',
      ]);
      expect(problems('show_tags:\n  - a\n  - [b]\n'), ['tidy_log.yaml: show_tags: expected a list of strings']);
      expect(problems('rules: {match: x}\n'), [
        'tidy_log.yaml: rules: expected a list of rules, each with match, label and tone',
      ]);
    });

    test('a bad pattern is reported with its key and index', () {
      expect(problems('hide_messages:\n  - ok\n  - "(unclosed"\n'), [
        startsWith('tidy_log.yaml: hide_messages[1]: invalid pattern "(unclosed"'),
      ]);
      expect(problems('rules:\n  - match: "[a-"\n'), [
        startsWith('tidy_log.yaml: rules[0]: match: invalid pattern "[a-"'),
      ]);
    });

    test('a rule without match or with an unknown tone is reported, not skipped', () {
      expect(problems('rules:\n  - label: SVG\n'), [
        'tidy_log.yaml: rules[0]: missing match (a pattern for the log text)',
      ]);
      expect(problems('rules:\n  - match: x\n    tone: loud\n'), [
        startsWith('tidy_log.yaml: rules[0]: tone: unknown tone "loud"'),
      ]);
    });

    test('every problem is reported at once', () {
      expect(problems('color: 1\nhide_tags: x\nhttp_rules:\n  - values: {1: success}\n'), [
        'tidy_log.yaml: color: expected true or false',
        'tidy_log.yaml: hide_tags: expected a list of strings',
        startsWith('tidy_log.yaml: http_rules[0]: missing field'),
      ]);
    });

    test('invalid YAML and a file that is not a map get one line each', () {
      expect(problems('hide_tags: [a, b\n'), [startsWith('tidy_log.yaml: not valid YAML (line ')]);
      expect(problems('- a\n- b\n'), [startsWith('tidy_log.yaml: expected settings as "key: value" lines')]);
    });

    test('NO_COLOR does not hide a mistyped color', () {
      expect(() => TidyConfig.fromYaml('color: yes please\n', color: false), throwsFormatException);
    });

    test('a valid file still reads as before', () {
      final config = TidyConfig.fromYaml('''
preset: all
hide_tags: [FlutterJNI, "cr_*"]
show_tags: [ImeTracker]
hide_messages: ['^GC freed']
min_native_level: WRN
project_packages: [core_kit]
color: false
max_width: 120
rules:
  - match: "^Svg"
    label: SVG
    tone: warning
  - match: cache
''', appPackage: 'my_app');
      expect(config.preset, Preset.all);
      expect(config.hideTags, ['FlutterJNI', 'cr_*']);
      expect(config.showTags, ['ImeTracker']);
      expect(config.hideMessages, ['^GC freed']);
      expect(config.minNativeLevel, Level.warning);
      expect(config.projectPackages, ['my_app', 'core_kit']);
      expect(config.color, isFalse);
      expect(config.maxWidth, 120);
      expect(config.rules.map((r) => (r.pattern.pattern, r.label, r.tone)), [
        ('^Svg', 'SVG', Tone.warning),
        ('cache', 'LOG', Tone.accent),
      ]);
      expect(TidyConfig.fromYaml(null).redactKeys, TidyConfig.defaultRedactKeys);
      expect(TidyConfig.fromYaml('redact_keys:\n').redactKeys, isEmpty);
      expect(TidyConfig.fromYaml('hide_tags:\n').hideTags, isEmpty);
    });
  });

  test('copyWith changes only what it is given, http_rules included', () {
    final config = TidyConfig.fromYaml('max_width: 99\nhttp_rules:\n  - field: type\n    values: {1: success}\n');
    final plain = config.copyWith(color: false);
    expect(plain.color, isFalse);
    expect(plain.maxWidth, 99);
    expect(plain.httpRules, same(config.httpRules));
    expect(plain.httpRules, hasLength(1));
    expect(plain.redactKeys, config.redactKeys);
  });
}
