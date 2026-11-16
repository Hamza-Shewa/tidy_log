## 0.1.0

First release.

- `dart run tidy_log run …`: runs `flutter run` (or `attach`) and restyles the device log. Native logcat prefixes become a dim tag suffix, repeats collapse to `×N`, Java and printed Dart traces lead with the first useful frame, Dio boxes (and pretty_dio_logger-style `╔╣ Request` / `╔╣ Response` boxes from any package, paired by URL) become one line with secrets and JWTs masked, and process and hot reload get dividers. A plain clean copy goes to `.dart_tool/tidy_log/last_run.log`.
- `dart run tidy_log:setup`: sets up VS Code (launcher scripts and "(tidy logs)" launch configs). `--remove` undoes it.
- `dart run tidy_log:setup --sdk`: a shim Flutter SDK (symlinks to your real SDK, which is never modified) for Android Studio and IntelliJ.
- In-app logger: `TidyLog.d/i/w/e`, `installErrorHooks()` for location-first Flutter and async errors, and `TidyDioInterceptor` with response rules for "200, but it failed" bodies.
- `tidy_log.yaml` for presets, hidden and shown tags, levels, redaction keys and label rules.
