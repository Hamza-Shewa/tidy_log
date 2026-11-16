import 'dart:convert';
import 'dart:io';

import 'package:yaml/yaml.dart';

import 'launch_json.dart';
import 'launchers.dart';
import 'sdk_shim.dart';

const setupUsage = '''
dart run tidy_log:setup [options]

VS Code (default): writes .vscode/tidy_flutter (and .bat) and adds a
"<name> (tidy logs)" copy of each Flutter run or attach config in
.vscode/launch.json (test configs get none). Your own configs and comments
are left as they are.

  --remove              undo: delete the tidy configs and launcher scripts
                        (ones you have edited are kept)
  --dry-run             print what would change, write nothing

Android Studio / IntelliJ (once per machine):

  --sdk                 create a shim Flutter SDK (links to your real SDK,
                        which is never modified) and point the IDE at it
  --sdk --remove        delete the shim
  --sdk-dir <path>      shim location (default ~/.tidy_log/flutter_sdk)
  --flutter-root <path> the real SDK (default: FLUTTER_ROOT or PATH)

Terminal: no setup needed, run `dart run tidy_log run -d <device>`.''';

/// What a setup run would write or delete, relative to the project root.
final class SetupPlan {
  SetupPlan(this.writes, this.deletes, this.notes, {this.makeExecutable = const [], this.launchJsonError});

  /// path → new content.
  final Map<String, String> writes;

  /// Files, then folders (`.vscode` once it would be empty).
  final List<String> deletes;
  final List<String> notes;

  /// Existing files that only need `chmod +x` (macOS and Linux).
  final List<String> makeExecutable;

  /// Why `.vscode/launch.json` could not be edited, when it could not. The
  /// launchers are still in the plan so the user can add the config by hand.
  final String? launchJsonError;

  bool get isEmpty => writes.isEmpty && deletes.isEmpty && makeExecutable.isEmpty;
}

/// Thrown for problems the user has to fix (wrong folder, broken JSON).
final class SetupException implements Exception {
  const SetupException(this.message);
  final String message;
  @override
  String toString() => message;
}

const _launchJson = '.vscode/launch.json';
const _bom = [0xEF, 0xBB, 0xBF];

/// Works out the project setup for [project] without touching the disk.
SetupPlan planProjectSetup(Directory project, {bool remove = false}) {
  _appPackage(project);
  final writes = <String, String>{};
  final deletes = <String>[];
  final notes = <String>[];
  final makeExecutable = <String>[];

  String? launchJsonError;
  var stillUsed = const <String>[];
  try {
    final launch = File('${project.path}/$_launchJson');
    final bytes = launch.existsSync() ? launch.readAsBytesSync() : null;
    // Dart's string reads drop a leading BOM; keep it so the rewrite does too.
    final hasBom = bytes != null && _startsWith(bytes, _bom);
    final source = bytes == null ? null : utf8.decode(hasBom ? bytes.sublist(_bom.length) : bytes);
    final edit = remove ? (source == null ? const LaunchEdit('') : removeTidyTwins(source)) : addTidyTwins(source);
    if (remove && edit.leftEmpty) {
      deletes.add(_launchJson);
    } else if (edit.changed) {
      writes[_launchJson] = hasBom ? '\uFEFF${edit.text}' : edit.text;
    }
    notes.addAll([
      for (final name in edit.added) 'added launch config "$name"',
      for (final name in edit.removed) 'removed launch config "$name"',
      for (final reason in edit.skipped) 'left as is: $reason',
      ...edit.notes,
    ]);
    stillUsed = edit.kept;
  } on LaunchJsonException catch (e) {
    launchJsonError = e.message;
  } on FormatException catch (e) {
    launchJsonError = 'it is not valid JSON or UTF-8 (${e.message})';
  }
  if (launchJsonError != null && remove) {
    throw SetupException(
      'Could not edit $_launchJson: $launchJsonError\n'
      'Nothing was removed: the launchers stay because launch.json may still use them.',
    );
  }

  for (final (path, content, previous) in [
    (launcherPath, shellLauncher, const <String>[]),
    ('$launcherPath.bat', batchLauncher, previousBatchLaunchers),
  ]) {
    final file = File('${project.path}/$path');
    final outdated = file.existsSync() && !_sameContent(file, content) && previous.any((p) => _sameContent(file, p));
    if (!file.existsSync()) {
      if (!remove) writes[path] = content;
    } else if (outdated && !remove) {
      writes[path] = content;
      notes.add('updated $path from an earlier version of tidy_log');
    } else if (!outdated && !_sameContent(file, content)) {
      // Teams may edit the committed launchers: never overwrite or delete those.
      notes.add(
        remove
            ? 'kept $path (it differs from the template; delete it by hand if you no longer need it)'
            : 'kept $path (it differs from the template; delete it and rerun to update)',
      );
    } else if (remove && stillUsed.isNotEmpty) {
      notes.add('kept $path (launch config "${stillUsed.first}" still uses it)');
    } else if (remove) {
      deletes.add(path);
    } else if (path == launcherPath && !Platform.isWindows && file.statSync().mode & 0x40 == 0) {
      // Lost through a zip or a checkout; VS Code cannot start it without.
      makeExecutable.add(path);
    }
  }

  if (remove) {
    final vscode = Directory('${project.path}/.vscode');
    // Drop .vscode too when setup's files were all that was left in it. Plan
    // paths use `/`; listSync gives `\` on Windows.
    String relative(FileSystemEntity e) => e.path.substring(project.path.length + 1).replaceAll(r'\', '/');
    if (deletes.isNotEmpty &&
        vscode.existsSync() &&
        vscode.listSync(followLinks: false).every((e) => deletes.contains(relative(e)))) {
      deletes.add('.vscode');
    }
  }
  return SetupPlan(writes, deletes, notes, makeExecutable: makeExecutable, launchJsonError: launchJsonError);
}

bool _startsWith(List<int> bytes, List<int> prefix) {
  if (bytes.length < prefix.length) return false;
  for (var i = 0; i < prefix.length; i++) {
    if (bytes[i] != prefix[i]) return false;
  }
  return true;
}

bool _sameContent(File file, String content) {
  final expected = utf8.encode(content);
  final actual = file.readAsBytesSync();
  return actual.length == expected.length && _startsWith(actual, expected);
}

/// Applies [plan] to [project]. The shell launcher is made executable, in
/// git too when git already tracks it. Returns notes for the user about git
/// (see [_gitFollowUp]).
List<String> applySetup(Directory project, SetupPlan plan) {
  for (final MapEntry(key: path, value: content) in plan.writes.entries) {
    final file = File('${project.path}/$path')..parent.createSync(recursive: true);
    file.writeAsStringSync(content);
    if (path == launcherPath && !Platform.isWindows) _makeExecutable(project, path);
  }
  for (final path in plan.makeExecutable) {
    _makeExecutable(project, path);
  }
  for (final path in plan.deletes) {
    final full = '${project.path}/$path';
    // Not recursive: a folder is only deleted when it is really empty.
    FileSystemEntity.isDirectorySync(full) ? Directory(full).deleteSync() : File(full).deleteSync();
  }
  return _gitFollowUp(
    project,
    shellLauncher: plan.writes.containsKey(launcherPath) || plan.makeExecutable.contains(launcherPath),
    batchLauncher: plan.writes.containsKey('$launcherPath.bat'),
  );
}

/// Git housekeeping for launchers that were just written, when [project]
/// is in a git work tree. The committed shell launcher must keep its
/// executable bit, which git cannot see on Windows (`core.fileMode` false):
/// if git already tracks the file, the bit is set in the index; otherwise
/// the user gets the command to run after `git add`. The batch launcher
/// needs CRLF line endings in every checkout, so a missing `eol=crlf`
/// attribute gets a note. `.gitattributes` itself is never edited.
List<String> _gitFollowUp(Directory project, {required bool shellLauncher, required bool batchLauncher}) {
  if (!shellLauncher && !batchLauncher) return const [];
  String? git(List<String> args) {
    try {
      final result = Process.runSync('git', args, workingDirectory: project.path);
      return result.exitCode == 0 ? '${result.stdout}'.trim() : null;
    } on ProcessException {
      return null; // no git on PATH
    }
  }

  if (git(['rev-parse', '--is-inside-work-tree']) != 'true') return const [];
  final notes = <String>[];
  if (shellLauncher) {
    if (git(['ls-files', '--error-unmatch', '--', launcherPath]) != null) {
      if (git(['update-index', '--chmod=+x', '--', launcherPath]) != null) {
        notes.add('set the executable bit of $launcherPath in git');
      }
    } else if (git(['config', '--get', 'core.fileMode']) == 'false') {
      notes.add(
        'git does not record executable bits here: after `git add`, run '
        '`git update-index --chmod=+x $launcherPath` so it starts on macOS and Linux',
      );
    }
  }
  if (batchLauncher && !(git(['check-attr', 'eol', '--', '$launcherPath.bat']) ?? '').endsWith(': crlf')) {
    notes.add('consider adding `*.bat text eol=crlf` to .gitattributes so $launcherPath.bat keeps CRLF line endings');
  }
  return notes;
}

void _makeExecutable(Directory project, String path) {
  final chmod = Process.runSync('chmod', ['+x', '${project.path}/$path']);
  if (chmod.exitCode != 0) throw SetupException('Could not make $path executable: ${chmod.stderr}');
}

/// Entry point of `bin/setup.dart`. Returns the exit code.
int runSetup(List<String> args, {Directory? project, IOSink? out, IOSink? err, Map<String, String>? environment}) {
  final sink = out ?? stdout;
  final errors = err ?? stderr;
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
        errors.writeln('$arg needs a path.\n\n$setupUsage');
        return 64;
      }
      values[arg] = args[++i];
    } else if (const {'--remove', '--dry-run', '--sdk'}.contains(arg)) {
      flags.add(arg);
    } else {
      errors.writeln('Unknown option: $arg\n\n$setupUsage');
      return 64;
    }
  }
  if (flags.contains('--sdk') || values.isNotEmpty) {
    return _runSdkSetup(
      sink,
      errors,
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
    errors.writeln('tidy_log setup: $e');
    return 1;
  } on FileSystemException catch (e) {
    errors.writeln('tidy_log setup: ${e.message} (${e.path})');
    return 1;
  }

  final launchJsonError = plan.launchJsonError;
  if (plan.isEmpty && launchJsonError == null) {
    final nothing = remove
        ? (plan.notes.isEmpty ? 'Nothing to remove: tidy_log is not set up here.' : 'Nothing removed.')
        : 'Already set up, nothing to change.';
    sink.writeln(nothing);
    for (final note in plan.notes) {
      sink.writeln('  $note');
    }
    return 0;
  }
  var gitNotes = const <String>[];
  if (!dryRun) {
    try {
      gitNotes = applySetup(dir, plan);
    } on SetupException catch (e) {
      errors.writeln('tidy_log setup: $e');
      return 1;
    } on FileSystemException catch (e) {
      errors.writeln('tidy_log setup: ${e.message} (${e.path})');
      return 1;
    }
  }
  final verb = dryRun ? 'would ' : '';
  for (final path in plan.writes.keys) {
    sink.writeln('  ${verb}write  $path');
  }
  for (final path in plan.makeExecutable) {
    sink.writeln('  ${verb}make executable $path');
  }
  for (final path in plan.deletes) {
    sink.writeln('  ${verb}delete $path');
  }
  for (final note in [...plan.notes, ...gitNotes]) {
    sink.writeln('  $note');
  }
  if (launchJsonError != null) {
    errors.writeln(
      'tidy_log setup: could not edit $_launchJson ($launchJsonError), '
      'so ${dryRun ? 'would leave' : 'left'} $_launchJson untouched.\n'
      'The launchers are ${dryRun ? 'not written (dry run)' : 'in place'}. '
      'Fix the file and rerun, or add this config to its "configurations" list by hand:\n'
      '${_snippet()}',
    );
    return 1;
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
  IOSink sink,
  IOSink errors, {
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
    errors.writeln('tidy_log setup: $e');
    return 1;
  } on FileSystemException catch (e) {
    errors.writeln('tidy_log setup: ${e.message} (${e.path})');
    return 1;
  }
}

/// The app's package name. Throws when [project] does not depend on tidy_log.
String? _appPackage(Directory project) {
  final pubspec = File('${project.path}/pubspec.yaml');
  if (!pubspec.existsSync()) {
    throw const SetupException('No pubspec.yaml here. Run this from your app\'s root folder.');
  }
  final Object? doc;
  try {
    doc = loadYaml(pubspec.readAsStringSync(), sourceUrl: pubspec.uri);
  } on YamlException catch (e) {
    throw SetupException('Could not read pubspec.yaml: ${e.message} (line ${(e.span?.start.line ?? 0) + 1})');
  }
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
