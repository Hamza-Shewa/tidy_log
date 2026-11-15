import 'dart:io';

import 'package:tidy_log_core/src/cli/flutter_wrapper.dart';

Future<void> main(List<String> args) async {
  exitCode = await runWrapper(args);
  await stdout.flush();
  exit(exitCode);
}
