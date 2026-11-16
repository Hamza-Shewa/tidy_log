import 'package:yaml/yaml.dart';

import '../entry.dart';
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
    this.maxWidth = 220,
    this.rules = const [],
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

  /// Parses `tidy_log.yaml`. [appPackage] (the `name:` from pubspec.yaml) is
  /// put first in [projectPackages] when the file does not list it.
  factory TidyConfig.fromYaml(String? source, {String? appPackage, bool? color}) {
    final doc = source == null || source.trim().isEmpty ? null : loadYaml(source);
    final map = doc is YamlMap ? doc : YamlMap();
    List<String> strings(String key) => [for (final v in (map[key] as YamlList?) ?? YamlList()) '$v'];

    final packages = strings('project_packages');
    if (appPackage != null && !packages.contains(appPackage)) packages.insert(0, appPackage);

    return TidyConfig(
      preset: map['preset'] == 'all' ? Preset.all : Preset.quiet,
      hideTags: strings('hide_tags'),
      showTags: strings('show_tags'),
      hideMessages: strings('hide_messages'),
      minNativeLevel: Level.values.firstWhere(
        (l) => l.name == map['min_native_level'] || l.label == '${map['min_native_level']}'.toUpperCase(),
        orElse: () => Level.debug,
      ),
      projectPackages: packages.isEmpty ? const ['app'] : packages,
      redactKeys: map.containsKey('redact_keys') ? strings('redact_keys') : defaultRedactKeys,
      color: color ?? (map['color'] as bool? ?? true),
      maxWidth: (map['max_width'] as int?) ?? 220,
      rules: [
        for (final rule in (map['rules'] as YamlList?) ?? YamlList())
          if (rule is YamlMap && rule['match'] != null)
            LabelRule(
              RegExp('${rule['match']}'),
              '${rule['label'] ?? 'LOG'}'.padRight(3).substring(0, 3),
              Tone.values.firstWhere((t) => t.name == rule['tone'], orElse: () => Tone.accent),
            ),
      ],
    );
  }
}
