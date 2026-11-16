import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tidy_log/src/core.dart';

/// Acceptance test: an excerpt of a real F5 session from a real app (PINs and
/// user IDs replaced) must clean up to the reviewed plain output.
///
/// To update after an intended change, regenerate the expected file with
/// `dart run bin/tidy_flutter.dart rewrite --plain` from a folder whose
/// tidy_log.yaml lists `project_packages: [app, core_kit]`, then review
/// the diff.
void main() {
  test('sample session cleans up to the expected output', () {
    final input = File('test/core/fixtures/sample_session.txt').readAsLinesSync();
    final expected = File('test/core/fixtures/sample_session.expected.txt').readAsLinesSync();

    final pipeline = ConsolePipeline(TidyConfig(projectPackages: const ['app', 'core_kit'], color: false));
    const renderer = Renderer(color: false);
    final actual = [
      for (final entry in [for (final l in input) ...pipeline.add(l), ...pipeline.flush()]) ...renderer.render(entry),
    ];

    expect(actual, expected);
    expect(actual.length, lessThan(input.length ~/ 2), reason: 'the cleaner should at least halve this session');
    expect(actual.join('\n'), isNot(contains('11112222')), reason: 'the PIN must be masked');
  });
}
