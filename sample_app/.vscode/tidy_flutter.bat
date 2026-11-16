@echo off
rem Added by `dart run tidy_log:setup`: runs flutter through tidy_log's log cleaner.
rem Falls back to plain flutter until `flutter pub get` has resolved tidy_log.
setlocal
if defined FLUTTER_ROOT (
  set "TIDY_ROOT=%FLUTTER_ROOT%"
) else (
  for %%i in (flutter.bat) do set "TIDY_ROOT=%%~dp$PATH:i.."
)
findstr /c:"\"name\": \"tidy_log\"" ".dart_tool\package_config.json" >nul 2>&1
if %errorlevel%==0 (
  call "%TIDY_ROOT%\bin\dart.bat" run tidy_log %*
) else (
  echo tidy_log is not resolved yet ^(run flutter pub get^); using plain flutter 1>&2
  call "%TIDY_ROOT%\bin\flutter.bat" %*
)
exit /b %errorlevel%
