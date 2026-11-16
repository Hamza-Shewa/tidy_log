import 'dart:io';

import 'package:tidy_log/src/cli/setup.dart';

/// `dart run tidy_log:setup`: sets up VS Code in the current project.
void main(List<String> args) {
  exitCode = runSetup(args);
}
