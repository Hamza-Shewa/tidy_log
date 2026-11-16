import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tidy_log/tidy_log.dart';

// Kept in its own file: this test needs FlutterError.onError to be untouched
// before installErrorHooks() runs, as in a real app's main().
void main() {
  test('in a fresh app the hooks take over without the "already set" hint', () {
    final printed = <String>[];
    TidyLog.configure(enabled: true, color: false, printer: printed.add);

    TidyLog.installErrorHooks();
    FlutterError.reportError(FlutterErrorDetails(exception: FlutterError('Bad state: no user')));

    expect(printed, isNot(contains(startsWith('WRN FlutterError.onError was already set'))));
    expect(printed.first, startsWith('ERR Bad state: no user'));
  });
}
