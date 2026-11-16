import 'dart:io';

import 'package:yaml/yaml.dart';

import 'launch_json.dart';
import 'launchers.dart';
import 'sdk_shim.dart';

const setupUsage = '''
dart run tidy_log:setup [options]

VS Code (default): writes .vscode/tidy_flutter (and .bat) and adds a
"<name> (tidy logs)" copy of each Dart launch config in .vscode/launch.json.
Your own configs and comments are left as they are.

  --remove              undo: delete the tidy configs and launcher scripts
  --dry-run             print what would change, write nothing

Android Studio / IntelliJ (once per machine):

  --sdk                 create a shim Flutter SDK (symlinks to your real SDK,
                        which is never modified) and point the IDE at it
  --sdk --remove        delete the shim
  --sdk-dir <path>      shim location (default ~/.tidy_log/flutter_sdk)
  --flutter-root <path> the real SDK (default: FLUTTER_ROOT or PATH)

Terminal: no setup needed, run `dart run tidy_log run -d <device>`.''';

/// What a setup run would write or delete, relative to the project root.
final class SetupPlan {
  SetupPlan(this.writes, this.deletes, this.notes);

  /// path → new content.
  final Map<String, String> writes;
  final List<String> deletes;
  final List<String> notes;

  bool get isEmpty => writes.isEmpty && deletes.isEmpty;
}

/// Thrown for problems the user has to fix (wrong folder, broken JSON).
final class SetupException implements Exception {
  const SetupException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Works out the project setup for [project] without touching the disk.
SetupPlan planProjectSetup(Directory project, {bool remove = false}) {
  _appPackage(project);
  final launch = File('${project.path}/.vscode/launch.json');
  final source = launch.existsSync() ? launch.readAsStringSync() : null;
  final writes = <String, String>{};
  final deletes = <String>[];
  final notes = <String>[];

  LaunchEdit edit;
  try {
    edit = remove
        ? (source == null ? const LaunchEdit('') : removeTidyTwins(source))
        : addTidyTwins(source);
  } on LaunchJsonException catch (e) {
    throw SetupException('Could not edit .vscode/launch.json: ${e.message}\nAdd this config by hand instead:\n'
        '${_snippet()}');
  }
  if (edit.changed) writes['.vscode/launch.json'] = edit.text;
  notes.addAll([
    for (final name in edit.added) 'added launch config "$name"',
    for (final name in edit.removed) 'removed launch config "$name"',
    for (final reason in edit.skipped) 'left as is: $reason',
  ]);

  for (final (path, content) in [(launcherPath, shellLauncher), ('$launcherPath.bat', batchLauncher)]) {
    final file = File('${project.path}/$path');
    if (remove) {
      if (file.existsSync()) deletes.add(path);
    } else if (!file.existsSync() || file.readAsStringSync() != content) {
      writes[path] = content;
    }
  }
  return SetupPlan(writes, deletes, notes);
}

/// Applies [plan] to [project]. The shell launcher is made executable.
void applySetup(Directory project, SetupPlan plan) {
  for (final MapEntry(key: path, value: content) in plan.writes.entries) {
    final file = File('${project.path}/$path')..parent.createSync(recursive: true);
    file.writeAsStringSync(content);
    if (path == launcherPath && !Platform.isWindows) {
      final chmod = Process.runSync('chmod', ['+x', file.path]);
      if (chmod.exitCode != 0) throw SetupException('Could not make $path executable: ${chmod.stderr}');
    }
  }
  for (final path in plan.deletes) {
    File('${project.path}/$path').deleteSync();
  }
}

/// Entry point of `bin/setup.dart`. Returns the exit code.
int runSetup(List<String> args, {Directory? project, IOSink? out, Map<String, String>? environment}) {
  final sink = out ?? stdout;
  if (args.contains('--help') || args.contains('-h')) {
    sink.writeln(setupUsage);
    return 0;
  }
  final flags = <String>{};
  final values = <String, String>{};
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg == '--sdk-dir' || arg == '--flutter-root') {
      if (i + 1 >= args.length) {
        stderr.writeln('$arg needs a path.\n\n$setupUsage');
        return 64;
      }
      values[arg] = args[++i];
    } else if (const {'--remove', '--dry-run', '--sdk'}.contains(arg)) {
      flags.add(arg);
    } else {
      stderr.writeln('Unknown option: $arg\n\n$setupUsage');
      return 64;
    }
  }
  if (flags.contains('--sdk') || values.isNotEmpty) {
    return _runSdkSetup(
      sink,
      remove: flags.contains('--remove'),
      dryRun: flags.contains('--dry-run'),
      shimPath: values['--sdk-dir'] ?? defaultShimPath(environment),
      flutterRoot: values['--flutter-root'],
      environment: environment,
    );
  }
  final projectFlags = flags;
  final dir = project ?? Directory.current;
  final remove = projectFlags.contains('--remove');
  final dryRun = projectFlags.contains('--dry-run');

  final SetupPlan plan;
  try {
    plan = planProjectSetup(dir, remove: remove);
  } on SetupException catch (e) {
    stderr.writeln('tidy_log setup: $e');
    return 1;
  }

  if (plan.isEmpty) {
    sink.writeln(remove ? 'Nothing to remove: tidy_log is not set up here.' : 'Already set up, nothing to change.');
    return 0;
  }
  if (!dryRun) applySetup(dir, plan);
  final verb = dryRun ? 'would ' : '';
  for (final path in plan.writes.keys) {
    sink.writeln('  ${verb}write  $path');
  }
  for (final path in plan.deletes) {
    sink.writeln('  ${verb}delete $path');
  }
  for (final note in plan.notes) {
    sink.writeln('  $note');
  }
  if (remove || dryRun) return 0;

  sink.writeln('''

Done. In VS Code, open Run and Debug, pick a "(tidy logs)" config and press F5.
Commit .vscode/tidy_flutter, .vscode/tidy_flutter.bat and .vscode/launch.json
so your team gets it too. Undo with: dart run tidy_log:setup --remove

Android Studio / IntelliJ: run `dart run tidy_log:setup --sdk` once per machine.
Terminal: `dart run tidy_log run -d <device>`.''');
  final app = _appPackage(dir);
  if (app != null) {
    sink.writeln('''

Optional, for TidyLog.d/i/w/e and the stronger error hooks, in lib/main.dart:

  import 'package:tidy_log/tidy_log.dart';

  void main() {
    TidyLog.configure(projectPackages: ['$app']);
    TidyLog.installErrorHooks(); // before Sentry or any other crash reporter
    runApp(const App());
  }''');
  }
  return 0;
}

int _runSdkSetup(
  IOSink sink, {
  required bool remove,
  required bool dryRun,
  required String shimPath,
  String? flutterRoot,
  Map<String, String>? environment,
}) {
  try {
    if (remove) {
      if (dryRun) {
        sink.writeln('  would delete $shimPath');
      } else {
        sink.writeln(removeShim(shimPath) ? '  deleted $shimPath' : 'No shim at $shimPath.');
      }
      if (!dryRun) sink.writeln('Point your IDE back at your real Flutter SDK if it still uses the shim.');
      return 0;
    }
    final real = findRealFlutterRoot(explicit: flutterRoot, environment: environment);
    if (dryRun) {
      sink.writeln('  would create $shimPath -> $real');
      return 0;
    }
    createShim(shimPath, real);
    sink.writeln('''  created $shimPath (links to $real; your SDK is not modified)

Android Studio / IntelliJ: Settings > Languages & Frameworks > Flutter >
Flutter SDK path: $shimPath
Then run the app as usual. Projects that depend on tidy_log get tidy logs
for run and attach; everything else behaves exactly like your real SDK.

Terminal (optional, to keep typing `flutter run`): put the shim first in PATH
  export PATH="$shimPath${Platform.pathSeparator}bin:\$PATH"

Rerun this after moving your Flutter SDK. Undo: dart run tidy_log:setup --sdk --remove''');
    return 0;
  } on ShimException catch (e) {
    stderr.writeln('tidy_log setup: $e');
    return 1;
  } on FileSystemException catch (e) {
    stderr.writeln('tidy_log setup: ${e.message} (${e.path})');
    return 1;
  }
}

/// The app's package name. Throws when [project] does not depend on tidy_log.
String? _appPackage(Directory project) {
  final pubspec = File('${project.path}/pubspec.yaml');
  if (!pubspec.existsSync()) {
    throw const SetupException('No pubspec.yaml here. Run this from your app\'s root folder.');
  }
  final doc = loadYaml(pubspec.readAsStringSync());
  final map = doc is YamlMap ? doc : YamlMap();
  bool lists(String section) => (map[section] as YamlMap?)?.containsKey('tidy_log') ?? false;
  if (map['name'] == 'tidy_log') {
    throw const SetupException('This is the tidy_log package itself. Run setup in an app that depends on it.');
  }
  if (!lists('dependencies') && !lists('dev_dependencies')) {
    throw const SetupException('pubspec.yaml does not list tidy_log. Add it first:\n  flutter pub add dev:tidy_log');
  }
  return map['name'] as String?;
}

String _snippet() => '''
    {
      "name": "Flutter (tidy logs)",
      "type": "dart",
      "request": "launch",
      "program": "lib/main.dart",
      "customTool": "\${workspaceFolder}/.vscode/tidy_flutter",
      "customToolReplacesArgs": 0,
      "windows": { "customTool": "\${workspaceFolder}\\\\.vscode\\\\tidy_flutter.bat" }
    }''';
