import 'dart:async';
import 'dart:io';

import 'package:tidy_log/src/cli/setup.dart';

/// `dart run tidy_log:setup`: sets up VS Code (or, with --sdk, the shim SDK).
void main(List<String> args) {
  // `dart run tidy_log:setup | head` closes stdout early; keep the exit code
  // instead of dying with a "Broken pipe" stack trace.
  unawaited(stdout.done.catchError((Object _) {}));
  exitCode = runSetup(args);
}
