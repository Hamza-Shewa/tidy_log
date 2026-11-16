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
const shellLauncher =
    '''
#!/bin/sh
# $_header
# Falls back to plain flutter until `flutter pub get` has resolved tidy_log.
if [ -n "\$FLUTTER_ROOT" ]; then
  root="\$FLUTTER_ROOT"
else
  flutter_bin="\$(command -v flutter)" || { echo "tidy_log: flutter not found on PATH" >&2; exit 127; }
  flutter_bin="\$(readlink -f "\$flutter_bin" 2>/dev/null || echo "\$flutter_bin")"
  root="\$(cd "\$(dirname "\$flutter_bin")/.." && pwd -P)"
fi
if grep -q '"name": "tidy_log"' .dart_tool/package_config.json 2>/dev/null; then
  exec "\$root/bin/dart" run tidy_log "\$@"
fi
echo "tidy_log is not resolved yet (run flutter pub get); using plain flutter" >&2
exec "\$root/bin/flutter" "\$@"
''';

/// `.vscode/tidy_flutter.bat` (Windows).
const batchLauncher =
    '''
@echo off
rem $_header
rem Falls back to plain flutter until `flutter pub get` has resolved tidy_log.
setlocal
if defined FLUTTER_ROOT (
  set "TIDY_ROOT=%FLUTTER_ROOT%"
) else (
  for %%i in (flutter.bat) do set "TIDY_ROOT=%%~dp\$PATH:i.."
)
findstr /c:"\\"name\\": \\"tidy_log\\"" ".dart_tool\\package_config.json" >nul 2>&1
if %errorlevel%==0 (
  call "%TIDY_ROOT%\\bin\\dart.bat" run tidy_log %*
) else (
  echo tidy_log is not resolved yet ^(run flutter pub get^); using plain flutter 1>&2
  call "%TIDY_ROOT%\\bin\\flutter.bat" %*
)
exit /b %errorlevel%
''';
