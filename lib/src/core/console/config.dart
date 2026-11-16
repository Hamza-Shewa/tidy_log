import 'package:yaml/yaml.dart';

import '../body_rule.dart';
import '../entry.dart';
import '../http_entry.dart';
import '../level.dart';

/// Which native lines are hidden by default.
enum Preset {
  /// Hides [quietTags] and [quietMessages] (Android UI and system chatter).
  quiet,

  /// Shows every line, still restyled.
  all,
}

/// Tags hidden by the `quiet` preset. `*` matches any run of characters.
const quietTags = <String>[
  'WindowOnBackDispatcher',
  'InsetsController',
  'ImeTracker',
  'InputConnectionAdaptor',
  'InputMethodManager*',
  'Surface',
  'HWUI',
  'nativeloader',
  'cr_*',
  'CompatChangeReporter',
  'Badge',
  'NexusLauncherBadge',
  'ApplicationLoaders',
  'ResourcesManager',
  'VRI[*',
  'ViewRootImpl',
  'WindowExtensionsImpl',
  'WindowLayoutComponentImpl',
  'UiContextUtils',
  'AudioSystem',
  'libc',
  'DefaultDispatch',
  'InteractionJankMonitor',
  'FlutterActivityAndFragmentDelegate',
  'ProfileInstaller',
  'DesktopExperienceFlags',
];

/// Message patterns hidden by the `quiet` preset, whatever the tag.
const quietMessages = <String>[
  r'avc: +(denied|granted)',
  r'^Compiler allocated',
  r'A resource failed to call ZipFile\.close',
  r'Access denied finding property',
  r'^Beginning load of flutter',
  r'was loaded normally!$',
  r'^Width is zero',
  r'GC freed \d+',
];

/// A user rule from `tidy_log.yaml`: Dart lines matching [pattern] get [label].
final class LabelRule {
  const LabelRule(this.pattern, this.label, this.tone);

  final RegExp pattern;
  final String label;
  final Tone tone;
}

/// Settings for the console cleaner. Read from `tidy_log.yaml` in the app
/// root; every field is optional.
final class TidyConfig {
  TidyConfig({
    this.preset = Preset.quiet,
    this.hideTags = const [],
    this.showTags = const [],
    this.hideMessages = const [],
    this.minNativeLevel = Level.debug,
    this.projectPackages = const ['app'],
    this.redactKeys = defaultRedactKeys,
    this.color = true,
    this.maxWidth = 160,
    this.rules = const [],
    this.httpRules = const [],
  });

  static const defaultRedactKeys = <String>[
    'pin',
    'password',
    'passcode',
    'otp',
    'token',
    'secret',
    'cvv',
    'authorization',
    'pincode',
    'otpcode',
    'cvv2',
    'cvc',
    'apikey',
    'cookie',
    'setcookie',
    'sessionid',
    'privatekey',
    'accesskey',
  ];

  final Preset preset;
  final List<String> hideTags;
  final List<String> showTags;
  final List<String> hideMessages;
  final Level minNativeLevel;

  /// The first entry is the app package itself (`lib/…` paths).
  final List<String> projectPackages;
  final List<String> redactKeys;
  final bool color;

  /// Head lines longer than this are shortened in the styled view.
  final int maxWidth;
  final List<LabelRule> rules;

  /// Judge pretty_dio_logger boxes by their response body (`http_rules`),
  /// like `ResponseRule.field` does in the app. The first verdict wins.
  final List<FieldRule> httpRules;

  /// A copy with the given fields replaced.
  TidyConfig copyWith({
    Preset? preset,
    List<String>? hideTags,
    List<String>? showTags,
    List<String>? hideMessages,
    Level? minNativeLevel,
    List<String>? projectPackages,
    List<String>? redactKeys,
    bool? color,
    int? maxWidth,
    List<LabelRule>? rules,
    List<FieldRule>? httpRules,
  }) => TidyConfig(
    preset: preset ?? this.preset,
    hideTags: hideTags ?? this.hideTags,
    showTags: showTags ?? this.showTags,
    hideMessages: hideMessages ?? this.hideMessages,
    minNativeLevel: minNativeLevel ?? this.minNativeLevel,
    projectPackages: projectPackages ?? this.projectPackages,
    redactKeys: redactKeys ?? this.redactKeys,
    color: color ?? this.color,
    maxWidth: maxWidth ?? this.maxWidth,
    rules: rules ?? this.rules,
    httpRules: httpRules ?? this.httpRules,
  );

  /// Parses `tidy_log.yaml`. [appPackage] (the `name:` from pubspec.yaml) is
  /// put first in [projectPackages] when the file does not list it.
  ///
  /// A mistake in the file throws a [FormatException] whose message has one
  /// line per problem, such as `tidy_log.yaml: hide_tags: expected a list of
  /// strings`. Every key is checked, so all problems are reported at once.
  factory TidyConfig.fromYaml(String? source, {String? appPackage, bool? color}) {
    final Object? doc;
    try {
      doc = source == null || source.trim().isEmpty ? null : loadYaml(source);
    } on YamlException catch (e) {
      throw FormatException('$_file: not valid YAML (line ${(e.span?.start.line ?? 0) + 1}: ${e.message})');
    }
    if (doc != null && doc is! YamlMap) {
      throw const FormatException('$_file: expected settings as "key: value" lines, such as preset: quiet');
    }
    final settings = _Settings(doc is YamlMap ? doc : YamlMap());

    final packages = settings.strings('project_packages') ?? [];
    if (appPackage != null && !packages.contains(appPackage)) packages.insert(0, appPackage);

    // Checked even when NO_COLOR overrides it, so a typo still shows up.
    final fileColor = settings.boolean('color');
    final config = TidyConfig(
      preset: settings.choice('preset', Preset.values, (p) => [p.name]) ?? Preset.quiet,
      hideTags: settings.strings('hide_tags') ?? const [],
      showTags: settings.strings('show_tags') ?? const [],
      hideMessages: settings.patterns('hide_messages') ?? const [],
      minNativeLevel: settings.choice('min_native_level', Level.values, (l) => [l.name, l.label]) ?? Level.debug,
      projectPackages: packages.isEmpty ? const ['app'] : packages,
      // `redact_keys:` with nothing after it turns masking off, as `[]` does.
      redactKeys: settings.has('redact_keys') ? (settings.strings('redact_keys') ?? const []) : defaultRedactKeys,
      color: color ?? fileColor ?? true,
      maxWidth: settings.width('max_width') ?? 160,
      rules: settings.list('rules', 'a list of rules, each with match, label and tone', _labelRule),
      httpRules: settings.list('http_rules', 'a list of rules', _httpRule),
    );
    if (settings.problems.isNotEmpty) throw FormatException(settings.problems.join('\n'));
    return config;
  }

  static const _file = 'tidy_log.yaml';

  /// One `http_rules` entry. A mistake is reported rather than skipped, so
  /// a typo never quietly turns a rule off.
  static FieldRule _httpRule(int index, Object? rule) {
    Never fail(String problem) => throw FormatException('tidy_log.yaml: http_rules[$index]: $problem');
    HttpOutcome outcome(Object? name) => HttpOutcome.values.firstWhere(
      (o) => o.name == '$name',
      orElse: () => fail('unknown outcome "$name" (use success, info, warning or error)'),
    );
    if (rule is! YamlMap) fail('expected field, values, otherwise and message keys');
    final field = rule['field'];
    if (field == null || '$field'.isEmpty) fail('missing field (the body path to look at, such as type)');
    final values = rule['values'];
    if (values != null && values is! YamlMap) fail('values must be a map, such as {1: success, 2: error}');
    return FieldRule(
      '$field',
      {for (final MapEntry(:key, :value) in ((values as YamlMap?) ?? YamlMap()).entries) key: outcome(value)},
      message: rule['message'] == null ? null : '${rule['message']}',
      otherwise: rule['otherwise'] == null ? null : outcome(rule['otherwise']),
    );
  }

  /// One `rules` entry: `match` (a pattern), optional `label` and `tone`.
  static LabelRule _labelRule(int index, Object? rule) {
    Never fail(String problem) => throw FormatException('$_file: rules[$index]: $problem');
    if (rule is! YamlMap) fail('expected match, label and tone keys');
    final match = rule['match'];
    if (match == null || '$match'.isEmpty) fail('missing match (a pattern for the log text)');
    if (match is YamlNode) fail('match: expected a pattern, not a list or map');
    final tone = rule['tone'];
    return LabelRule(
      _Settings.regExp('$match', (problem) => fail('match: $problem')),
      '${rule['label'] ?? 'LOG'}'.padRight(3).substring(0, 3),
      tone == null
          ? Tone.accent
          : Tone.values.firstWhere(
              (t) => t.name == '$tone',
              orElse: () => fail('tone: unknown tone "$tone" (use ${Tone.values.map((t) => t.name).join(', ')})'),
            ),
    );
  }
}

/// Reads and checks the keys of `tidy_log.yaml`, collecting every problem.
final class _Settings {
  _Settings(this._map);

  final YamlMap _map;
  final problems = <String>[];

  void _problem(String key, String text) => problems.add('${TidyConfig._file}: $key: $text');

  bool has(String key) => _map.containsKey(key);

  /// A list of plain values. Null when the key is missing, empty or wrong.
  List<String>? strings(String key) {
    final value = _map[key];
    if (value == null) return null;
    if (value is! YamlList || value.any((v) => v == null || v is YamlList || v is YamlMap)) {
      _problem(key, 'expected a list of strings');
      return null;
    }
    return [for (final v in value) '$v'];
  }

  /// A list of regular expressions, each checked.
  List<String>? patterns(String key) {
    final list = strings(key);
    if (list == null) return null;
    var ok = true;
    for (final (i, pattern) in list.indexed) {
      regExp(pattern, (problem) {
        _problem('$key[$i]', problem);
        ok = false;
      });
    }
    return ok ? list : null;
  }

  T? choice<T>(String key, List<T> values, List<String> Function(T) names) {
    final value = _map[key];
    if (value == null) return null;
    final text = '$value'.toLowerCase();
    for (final v in values) {
      if (names(v).any((n) => n.toLowerCase() == text) && value is! YamlNode) return v;
    }
    _problem(key, 'expected one of ${values.map((v) => names(v).first).join(', ')}');
    return null;
  }

  bool? boolean(String key) {
    final value = _map[key];
    if (value == null || value is bool) return value as bool?;
    _problem(key, 'expected true or false');
    return null;
  }

  int? width(String key) {
    final value = _map[key];
    if (value == null) return null;
    if (value is int && value > 0) return value;
    _problem(key, 'expected a whole number above 0, such as 120');
    return null;
  }

  /// A list whose items [item] reads; an item's [FormatException] becomes a
  /// problem and the item is left out.
  List<T> list<T>(String key, String expected, T Function(int index, Object? item) item) {
    final value = _map[key];
    if (value == null) return const [];
    if (value is! YamlList) {
      _problem(key, 'expected $expected');
      return const [];
    }
    final out = <T>[];
    for (final (i, entry) in value.indexed) {
      try {
        out.add(item(i, entry));
      } on FormatException catch (e) {
        problems.add(e.message);
      }
    }
    return out;
  }

  /// Compiles [pattern], or reports why it is not a valid pattern.
  static RegExp regExp(String pattern, void Function(String problem) onError) {
    try {
      return RegExp(pattern);
    } on FormatException catch (e) {
      onError('invalid pattern "$pattern" (${e.message})');
      return RegExp(r'(?!)');
    }
  }
}
