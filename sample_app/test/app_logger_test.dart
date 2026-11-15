import 'package:flutter_test/flutter_test.dart';
import 'package:tidy_log/tidy_log.dart';
import 'package:tidy_log_sample/demos/dart_error_demo.dart';
import 'package:tidy_log_sample/logging/app_logger.dart';

void main() {
  group('PlainAppLogger', () {
    test('prints the tagged message, the error and the full stack, unmasked', () {
      final printed = <String>[];
      final logger = PlainAppLogger(printer: (line, {wrapWidth}) => printed.add(line ?? ''));
      final stack = StackTrace.fromString('#0      main (package:tidy_log_sample/main.dart:1:1)');

      logger.i('Signed in {pin: 1234}', tag: 'Auth');
      logger.e('Transfer failed', tag: 'Api', error: const FormatException('bad amount'), stackTrace: stack);

      expect(printed, [
        'I [Auth] Signed in {pin: 1234}',
        'E [Api] Transfer failed',
        'FormatException: bad amount',
        '#0      main (package:tidy_log_sample/main.dart:1:1)',
      ]);
    });
  });

  group('TidyAppLogger', () {
    late List<String> printed;

    setUp(() {
      printed = [];
      TidyLog.reset();
      TidyLog.configure(enabled: true, color: false, printer: printed.add, projectPackages: ['tidy_log_sample']);
    });
    tearDown(TidyLog.reset);

    test('masks the PIN and labels the level', () {
      const TidyAppLogger().i('Signed in {pin: 1234}', tag: 'Auth');
      expect(printed.single, startsWith('INF Signed in {pin: ••••••••}'));
    });

    test('a caught error points at the throwing line in this app', () {
      DartErrorDemo(const TidyAppLogger()).caughtFormatError();

      expect(printed.first, startsWith('ERR Could not parse the amount'));
      expect(printed, contains(matches(RegExp(r'^    at lib/demos/dart_error_demo\.dart:\d+:\d+  DartErrorDemo\._parseAmount$'))));
    });
  });
}
