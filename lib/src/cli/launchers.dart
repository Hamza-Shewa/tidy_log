/// The launcher scripts `dart run tidy_log:setup` writes to `.vscode/`.
///
/// VS Code's `customTool` must be a single executable, so these small
/// scripts start `dart run tidy_log …` with the project's own Flutter SDK.
/// They are meant to be committed, so teammates get them too. Before
/// `flutter pub get` has resolved tidy_log they fall back to plain flutter,
/// so a fresh clone never fails to launch.
library;

const _header = 'Added by `dart run tidy_log:setup`: runs flutter through tidy_log\'s log cleaner.';

/// `.vscode/tidy_flutter` (macOS and Linux).
///
/// The SDK is `FLUTTER_ROOT`, else an fvm SDK at `.fvm/flutter_sdk`, else
/// `flutter` on PATH. tidy_log counts as resolved when the nearest
/// `.dart_tool/package_config.json` up the tree lists it, which also covers
/// pub workspace members (their package config lives at the workspace root).
const shellLauncher =
    '''
#!/bin/sh
# $_header
# Falls back to plain flutter until `flutter pub get` has resolved tidy_log.
if [ -n "\$FLUTTER_ROOT" ]; then
  root="\$FLUTTER_ROOT"
elif [ -x .fvm/flutter_sdk/bin/flutter ]; then
  root="\$(cd .fvm/flutter_sdk && pwd -P)"
else
  flutter_bin="\$(command -v flutter)" || { echo "tidy_log: flutter not found on PATH" >&2; exit 127; }
  flutter_bin="\$(readlink -f "\$flutter_bin" 2>/dev/null || echo "\$flutter_bin")"
  root="\$(cd "\$(dirname "\$flutter_bin")/.." && pwd -P)"
fi
dir="\$(pwd)"
while [ ! -f "\$dir/.dart_tool/package_config.json" ] && [ "\$dir" != / ]; do dir="\$(dirname "\$dir")"; done
if grep -q '"name": "tidy_log"' "\$dir/.dart_tool/package_config.json" 2>/dev/null; then
  exec "\$root/bin/dart" run tidy_log "\$@"
fi
echo "tidy_log is not resolved yet (run flutter pub get); using plain flutter" >&2
exec "\$root/bin/flutter" "\$@"
''';

/// `.vscode/tidy_flutter.bat` (Windows), with CRLF line endings: cmd.exe
/// can misread labels in LF-only batch files.
///
/// Same lookup as [shellLauncher]. It uses `goto` rather than `( )` blocks
/// so that paths with brackets in them, like `C:\Program Files (x86)`, are
/// safe, and keeps delayed expansion off so a `!` in an argument survives.
final batchLauncher = _batchLauncherLf.replaceAll('\n', '\r\n');

/// Earlier versions of [batchLauncher]. Setup updates them (and `--remove`
/// deletes them) as it does the current one; only files a team edited are
/// left alone.
final previousBatchLaunchers = [
  // Up to 0.2.0: the SDK path was expanded twice by `call`, which broke a
  // path with a percent sign in it.
  batchLauncher.replaceFirst(_callNote, '').replaceAll('"%%TIDY_ROOT%%', '"%TIDY_ROOT%'),
];

const _callNote =
    'rem call expands the line a second time, so the SDK path is only expanded\r\n'
    'rem then: a percent sign in it is not read as the start of a variable.\r\n';

const _batchLauncherLf =
    '''
@echo off
rem $_header
rem Falls back to plain flutter until `flutter pub get` has resolved tidy_log.
setlocal DisableDelayedExpansion
set "TIDY_ROOT="
if defined FLUTTER_ROOT set "TIDY_ROOT=%FLUTTER_ROOT%"
if not defined TIDY_ROOT if exist ".fvm\\flutter_sdk\\bin\\flutter.bat" set "TIDY_ROOT=%CD%\\.fvm\\flutter_sdk"
if not defined TIDY_ROOT for %%i in (flutter.bat) do if not "%%~\$PATH:i"=="" set "TIDY_ROOT=%%~dp\$PATH:i.."
if defined TIDY_ROOT goto find_root_done
echo tidy_log: flutter not found on PATH 1>&2
exit /b 127
:find_root_done
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
rem call expands the line a second time, so the SDK path is only expanded
rem then: a percent sign in it is not read as the start of a variable.
call "%%TIDY_ROOT%%\\bin\\dart.bat" run tidy_log %*
exit /b %errorlevel%
:plain
echo tidy_log is not resolved yet ^(run flutter pub get^); using plain flutter 1>&2
call "%%TIDY_ROOT%%\\bin\\flutter.bat" %*
exit /b %errorlevel%
''';
