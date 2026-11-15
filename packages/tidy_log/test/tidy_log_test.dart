import 'package:flutter_test/flutter_test.dart';
import 'package:tidy_log/tidy_log.dart';
import 'package:tidy_log_core/tidy_log_core.dart' show stripAnsi;

final _stack = StackTrace.fromString('''
#0      _InkResponseState.handleTap (package:flutter/src/material/ink_well.dart:1224:21)
#1      HomePage._onTap (package:app/app/view/home_page.dart:145:12)
#2      HomePage.build.<anonymous closure> (package:app/app/view/home_page.dart:98:5)
#3      GestureRecognizer.invokeCallback (package:flutter/src/gestures/recognizer.dart:345:24)
''');

void main() {
  late List<String> printed;

  setUp(() {
    printed = [];
    TidyLog.reset();
    TidyLog.configure(enabled: true, printer: printed.add);
  });
  tearDown(TidyLog.reset);

  test('an error log leads with your frame, then the trail, then the hidden count', () {
    TidyLog.e('Bad state: no user', tag: 'HomePage', stackTrace: _stack);
    expect(printed.map(stripAnsi).map((l) => l.replaceAll(RegExp(r' {2,}·'), '  ·')), [
      'ERR Bad state: no user  · HomePage',
      '    at lib/app/view/home_page.dart:145:12  HomePage._onTap',
      '    ┊ lib/app/view/home_page.dart:98:5  HomePage.build.<fn>',
      '    ┊ … 2 frames hidden',
    ]);
  });

  test('every coloured line starts with a reset so the wrapper passes it through', () {
    TidyLog.e('boom', stackTrace: _stack);
    expect(printed, everyElement(startsWith('\x1B[0m')));
    expect(printed.first, contains('\x1B[1;31m'));
  });

  test('plain mode prints no escape codes', () {
    TidyLog.configure(color: false);
    TidyLog.w('careful', error: StateError('x'));
    expect(printed, ['WRN careful', '    Bad state: x']);
  });

  test('levels below minLevel and a disabled logger print nothing', () {
    TidyLog.configure(minLevel: Level.warning);
    TidyLog.d('debug');
    TidyLog.i('info');
    expect(printed, isEmpty);
    TidyLog.configure(minLevel: Level.debug, enabled: false);
    TidyLog.e('error');
    expect(printed, isEmpty);
  });

  test('messages are redacted', () {
    TidyLog.configure(color: false);
    TidyLog.i('login {userId: 7, pin: 4321}');
    expect(printed.single, 'INF login {userId: 7, pin: ••••••••}');
  });

  test('projectPackages decides which frames lead', () {
    TidyLog.configure(color: false, projectPackages: ['other']);
    TidyLog.e('boom', stackTrace: _stack);
    expect(printed[1], '    at package:app/app/view/home_page.dart:145:12  HomePage._onTap',
        reason: 'no "other" frame, so the first non-SDK frame is used');
  });
}
