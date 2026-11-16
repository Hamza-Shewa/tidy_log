@echo off
rem Added by `dart run tidy_log:setup`: runs flutter through tidy_log's log cleaner.
rem Falls back to plain flutter until `flutter pub get` has resolved tidy_log.
setlocal DisableDelayedExpansion
set "TIDY_ROOT="
if defined FLUTTER_ROOT set "TIDY_ROOT=%FLUTTER_ROOT%"
if not defined TIDY_ROOT if exist ".fvm\flutter_sdk\bin\flutter.bat" set "TIDY_ROOT=%CD%\.fvm\flutter_sdk"
if not defined TIDY_ROOT for %%i in (flutter.bat) do if not "%%~$PATH:i"=="" set "TIDY_ROOT=%%~dp$PATH:i.."
if defined TIDY_ROOT goto find_root_done
echo tidy_log: flutter not found on PATH 1>&2
exit /b 127
:find_root_done
rem The nearest package config up the tree: a pub workspace member has none
rem of its own; it lives at the workspace root.
set "TIDY_DIR=%CD%"
:find_config
if exist "%TIDY_DIR%\.dart_tool\package_config.json" goto check_config
for %%d in ("%TIDY_DIR%\..") do set "TIDY_UP=%%~fd"
if /i "%TIDY_UP%"=="%TIDY_DIR%" goto plain
set "TIDY_DIR=%TIDY_UP%"
goto find_config
:check_config
findstr /c:"\"name\": \"tidy_log\"" "%TIDY_DIR%\.dart_tool\package_config.json" >nul 2>&1 || goto plain
call "%TIDY_ROOT%\bin\dart.bat" run tidy_log %*
exit /b %errorlevel%
:plain
echo tidy_log is not resolved yet ^(run flutter pub get^); using plain flutter 1>&2
call "%TIDY_ROOT%\bin\flutter.bat" %*
exit /b %errorlevel%
