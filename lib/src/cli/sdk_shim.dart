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
        (throw ShimException('$explicit is not a Flutter SDK (no bin/$exe or bin/cache). Run flutter once to set it up.'));
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
void createShim(String shimPath, String realRoot) {
  if (!Directory('$realRoot/bin').existsSync()) throw ShimException('$realRoot is not a Flutter SDK.');
  final shim = Directory(shimPath);
  if (Directory(realRoot).absolute.path == shim.absolute.path) throw const ShimException('The shim cannot point at itself.');
  if (shim.existsSync()) {
    if (!File('$shimPath/$shimMarker').existsSync()) {
      throw ShimException('$shimPath exists and is not a tidy_log shim. Choose another folder with --sdk-dir.');
    }
    shim.deleteSync(recursive: true);
  }
  shim.createSync(recursive: true);
  final real = Directory(realRoot);

  for (final entity in real.listSync(followLinks: false)) {
    final name = entity.uri.pathSegments.where((s) => s.isNotEmpty).last;
    if (name == 'bin') continue;
    _link('$shimPath/$name', entity);
  }
  Directory('$shimPath/bin').createSync();
  for (final entity in Directory('$realRoot/bin').listSync(followLinks: false)) {
    final name = entity.uri.pathSegments.where((s) => s.isNotEmpty).last;
    if (name == 'flutter' || name == 'flutter.bat') continue;
    _link('$shimPath/bin/$name', entity);
  }

  final sh = File('$shimPath/bin/flutter')..writeAsStringSync(shimShellScript(realRoot));
  File('$shimPath/bin/flutter.bat').writeAsStringSync(shimBatchScript(realRoot));
  if (!Platform.isWindows) {
    final chmod = Process.runSync('chmod', ['+x', sh.path]);
    if (chmod.exitCode != 0) throw ShimException('Could not make ${sh.path} executable: ${chmod.stderr}');
  }
  File('$shimPath/$shimMarker').writeAsStringSync('$realRoot\n');
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
String shimShellScript(String realRoot) => '''
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
      if grep -q '"name": "tidy_log"' .dart_tool/package_config.json 2>/dev/null; then
        TIDY_FLUTTER_BIN="\$real/bin/flutter" exec "\$real/bin/dart" run tidy_log "\$@"
      fi
      ;;
  esac
fi
exec "\$real/bin/flutter" "\$@"
''';

/// The shim's `bin/flutter.bat` (Windows).
String shimBatchScript(String realRoot) => '''
@echo off
rem tidy_log shim, created by `dart run tidy_log:setup --sdk`.
rem Sends `flutter run` and `flutter attach` through tidy_log in projects that
rem depend on it; everything else goes straight to the real Flutter SDK.
setlocal EnableDelayedExpansion
set "TIDY_REAL=$realRoot"
set "FLUTTER_ROOT=%TIDY_REAL%"
if defined TIDY_LOG_WRAPPED goto plain
set "TIDY_CMD="
for %%a in (%*) do (
  if not defined TIDY_CMD (
    set "TIDY_ARG=%%~a"
    if not "!TIDY_ARG:~0,1!"=="-" set "TIDY_CMD=!TIDY_ARG!"
  )
)
if /i "%TIDY_CMD%"=="run" goto tidy
if /i "%TIDY_CMD%"=="attach" goto tidy
goto plain
:tidy
findstr /c:"\\"name\\": \\"tidy_log\\"" ".dart_tool\\package_config.json" >nul 2>&1 || goto plain
set "TIDY_FLUTTER_BIN=%TIDY_REAL%\\bin\\flutter.bat"
call "%TIDY_REAL%\\bin\\dart.bat" run tidy_log %*
exit /b %errorlevel%
:plain
call "%TIDY_REAL%\\bin\\flutter.bat" %*
exit /b %errorlevel%
''';
