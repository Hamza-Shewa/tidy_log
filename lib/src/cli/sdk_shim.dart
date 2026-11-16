import 'dart:io';

/// Name of the marker file that identifies a shim folder. Setup only ever
/// deletes or refreshes a folder that has it.
const shimMarker = '.tidy_log_shim';

/// The default shim location: `~/.tidy_log/flutter_sdk`.
String defaultShimPath([Map<String, String>? environment]) {
  final env = environment ?? Platform.environment;
  final home = env['HOME'] ?? env['USERPROFILE'] ?? '.';
  return '$home${Platform.pathSeparator}.tidy_log${Platform.pathSeparator}flutter_sdk';
}

/// Thrown for problems the user has to fix.
final class ShimException implements Exception {
  const ShimException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Finds the real Flutter SDK root: [explicit], then `FLUTTER_ROOT`, then
/// `flutter` on `PATH` (symlinks resolved). A shim is never returned: if one
/// is found, the real root recorded in its marker is used instead.
String findRealFlutterRoot({String? explicit, Map<String, String>? environment}) {
  final env = environment ?? Platform.environment;
  final exe = Platform.isWindows ? 'flutter.bat' : 'flutter';

  String? resolve(String candidate) {
    final marker = File('$candidate/$shimMarker');
    final root = marker.existsSync() ? marker.readAsStringSync().trim() : candidate;
    final ok = File('$root/bin/$exe').existsSync() && Directory('$root/bin/cache').existsSync();
    return ok ? Directory(root).resolveSymbolicLinksSync() : null;
  }

  if (explicit != null) {
    return resolve(explicit) ??
        (throw ShimException(
          '$explicit is not a Flutter SDK (no bin/$exe or bin/cache). Run flutter once to set it up.',
        ));
  }
  final candidates = <String>[
    ?env['FLUTTER_ROOT'],
    for (final dir in (env['PATH'] ?? '').split(Platform.isWindows ? ';' : ':'))
      if (dir.isNotEmpty && File('$dir/$exe').existsSync())
        File(File('$dir/$exe').resolveSymbolicLinksSync()).parent.parent.path,
  ];
  for (final candidate in candidates) {
    final root = resolve(candidate);
    if (root != null) return root;
  }
  throw const ShimException('Could not find your Flutter SDK. Pass --flutter-root <path>.');
}

/// Creates (or refreshes) the shim at [shimPath] for the SDK at [realRoot].
///
/// Every top-level entry of the real SDK, and everything in its `bin/`
/// except `flutter` and `flutter.bat`, is linked. Those two become small
/// scripts that send `run` and `attach` through `dart run tidy_log` in
/// projects that depend on tidy_log, and everything else straight to the
/// real flutter. Nothing in the real SDK is modified.
///
/// The new shim is built in a sibling temp folder and swapped in by rename,
/// so a failure part-way leaves any existing shim as it was, and never a
/// half-built folder without a marker that setup would then refuse to touch.
void createShim(String shimPath, String realRoot) {
  if (!Directory('$realRoot/bin').existsSync()) throw ShimException('$realRoot is not a Flutter SDK.');
  final shim = Directory(shimPath.replaceFirst(RegExp(r'(?<=.)[/\\]+$'), '')).absolute;
  if (Directory(realRoot).absolute.path == shim.path) {
    throw const ShimException('The shim cannot point at itself.');
  }
  if (shim.existsSync() && !File('${shim.path}/$shimMarker').existsSync()) {
    throw ShimException('$shimPath exists and is not a tidy_log shim. Choose another folder with --sdk-dir.');
  }

  final staging = Directory('${shim.path}.tmp-$pid');
  try {
    if (staging.existsSync()) staging.deleteSync(recursive: true);
    staging.createSync(recursive: true);
    // Marker first: whatever happens next, the folder is recognisably ours.
    File('${staging.path}/$shimMarker').writeAsStringSync('$realRoot\n');
    _buildShim(staging.path, realRoot);
  } catch (_) {
    _deleteQuietly(staging);
    rethrow;
  }

  if (!shim.existsSync()) {
    staging.renameSync(shim.path);
    return;
  }
  final old = shim.renameSync('${shim.path}.old-$pid');
  try {
    staging.renameSync(shim.path);
  } catch (_) {
    old.renameSync(shim.path);
    _deleteQuietly(staging);
    rethrow;
  }
  // The new shim is in place. The old one only holds links and scripts, and
  // has the marker, so if it cannot be deleted the leftover is harmless.
  _deleteQuietly(old);
}

/// Best-effort cleanup that never hides the error being handled.
void _deleteQuietly(Directory dir) {
  try {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  } on FileSystemException {
    // Nothing more to do; the caller is already reporting the real problem.
  }
}

/// Fills [dir] with links to [realRoot] and the two router scripts.
void _buildShim(String dir, String realRoot) {
  final real = Directory(realRoot);
  for (final entity in real.listSync(followLinks: false)) {
    final name = entity.uri.pathSegments.where((s) => s.isNotEmpty).last;
    if (name == 'bin') continue;
    _link('$dir/$name', entity);
  }
  Directory('$dir/bin').createSync();
  for (final entity in Directory('$realRoot/bin').listSync(followLinks: false)) {
    final name = entity.uri.pathSegments.where((s) => s.isNotEmpty).last;
    if (name == 'flutter' || name == 'flutter.bat') continue;
    _link('$dir/bin/$name', entity);
  }

  final sh = File('$dir/bin/flutter')..writeAsStringSync(shimShellScript(realRoot));
  File('$dir/bin/flutter.bat').writeAsStringSync(shimBatchScript(realRoot));
  if (!Platform.isWindows) {
    final chmod = Process.runSync('chmod', ['+x', sh.path]);
    if (chmod.exitCode != 0) throw ShimException('Could not make ${sh.path} executable: ${chmod.stderr}');
  }
}

/// Deletes the shim at [shimPath]. Returns false when there is none.
bool removeShim(String shimPath) {
  final shim = Directory(shimPath);
  if (!shim.existsSync()) return false;
  if (!File('$shimPath/$shimMarker').existsSync()) {
    throw ShimException('$shimPath is not a tidy_log shim; not deleting it.');
  }
  shim.deleteSync(recursive: true);
  return true;
}

/// Links [path] to [target]. On Windows, where file symlinks need extra
/// rights, plain files are copied instead (folders become junctions).
void _link(String path, FileSystemEntity target) {
  final targetPath = target.absolute.path;
  if (Platform.isWindows && target is File) {
    target.copySync(path);
  } else {
    Link(path).createSync(targetPath);
  }
}

String _shQuote(String s) => "'${s.replaceAll("'", r"'\''")}'";

/// The shim's `bin/flutter` (macOS and Linux).
String shimShellScript(String realRoot) =>
    '''
#!/bin/sh
# tidy_log shim, created by `dart run tidy_log:setup --sdk`.
# Sends `flutter run` and `flutter attach` through tidy_log in projects that
# depend on it; everything else goes straight to the real Flutter SDK, which
# this shim never modifies. Remove with `dart run tidy_log:setup --sdk --remove`.
real=${_shQuote(realRoot)}
export FLUTTER_ROOT="\$real"
if [ -z "\$TIDY_LOG_WRAPPED" ]; then
  cmd=""
  for arg in "\$@"; do
    case "\$arg" in -*) ;; *) cmd="\$arg"; break ;; esac
  done
  case "\$cmd" in
    run|attach)
      # The nearest package config up the tree: a pub workspace member has
      # none of its own; it lives at the workspace root.
      dir="\$(pwd)"
      while [ ! -f "\$dir/.dart_tool/package_config.json" ] && [ "\$dir" != / ]; do dir="\$(dirname "\$dir")"; done
      if grep -q '"name": "tidy_log"' "\$dir/.dart_tool/package_config.json" 2>/dev/null; then
        TIDY_FLUTTER_BIN="\$real/bin/flutter" exec "\$real/bin/dart" run tidy_log "\$@"
      fi
      ;;
  esac
fi
exec "\$real/bin/flutter" "\$@"
''';

/// The shim's `bin/flutter.bat` (Windows), with CRLF line endings: cmd.exe
/// can misread labels in LF-only batch files.
///
/// Delayed expansion is only ever on inside `:scan`. Anywhere else it would
/// eat every `!` in the arguments passed on with `%*` (for example
/// `--dart-define=GREETING=Hello!`). So the main part runs with it off, and
/// `:scan` looks for the command in its own setlocal, handing back only a
/// fixed word (`tidy` or `plain`) across its endlocal.
String shimBatchScript(String realRoot) =>
    '''
@echo off
rem tidy_log shim, created by `dart run tidy_log:setup --sdk`.
rem Sends `flutter run` and `flutter attach` through tidy_log in projects that
rem depend on it; everything else goes straight to the real Flutter SDK.
rem Delayed expansion stays off here, so a ! in an argument is passed on intact.
setlocal DisableDelayedExpansion
set "TIDY_REAL=$realRoot"
set "FLUTTER_ROOT=%TIDY_REAL%"
if defined TIDY_LOG_WRAPPED goto plain
call :scan %*
if not "%TIDY_ROUTE%"=="tidy" goto plain
rem The nearest package config up the tree: a pub workspace member has none
rem of its own; it lives at the workspace root.
set "TIDY_DIR=%CD%"
:find_config
if exist "%TIDY_DIR%\\.dart_tool\\package_config.json" goto check_config
for %%d in ("%TIDY_DIR%\\..") do set "TIDY_UP=%%~fd"
if /i "%TIDY_UP%"=="%TIDY_DIR%" goto plain
set "TIDY_DIR=%TIDY_UP%"
goto find_config
:check_config
findstr /c:"\\"name\\": \\"tidy_log\\"" "%TIDY_DIR%\\.dart_tool\\package_config.json" >nul 2>&1 || goto plain
set "TIDY_FLUTTER_BIN=%TIDY_REAL%\\bin\\flutter.bat"
call "%TIDY_REAL%\\bin\\dart.bat" run tidy_log %*
exit /b %errorlevel%
:plain
call "%TIDY_REAL%\\bin\\flutter.bat" %*
exit /b %errorlevel%

:scan
rem Sets TIDY_ROUTE to tidy when the first argument that is not a -flag is
rem run or attach, else to plain. The only place delayed expansion is on.
setlocal EnableDelayedExpansion
set "TIDY_CMD="
for %%a in (%*) do (
  if not defined TIDY_CMD (
    set "TIDY_ARG=%%~a"
    if not "!TIDY_ARG:~0,1!"=="-" set "TIDY_CMD=!TIDY_ARG!"
  )
)
set "TIDY_ROUTE=plain"
if /i "!TIDY_CMD!"=="run" set "TIDY_ROUTE=tidy"
if /i "!TIDY_CMD!"=="attach" set "TIDY_ROUTE=tidy"
endlocal & set "TIDY_ROUTE=%TIDY_ROUTE%"
exit /b 0
'''
        .replaceAll('\n', '\r\n');
