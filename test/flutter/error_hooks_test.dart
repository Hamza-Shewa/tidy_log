import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tidy_log/tidy_log.dart';

FlutterErrorDetails _details(String message, {StackTrace? stack, InformationCollector? info}) => FlutterErrorDetails(
  exception: FlutterError(message),
  stack: stack,
  library: 'widgets library',
  informationCollector: info,
);

final _frameworkStack = StackTrace.fromString('''
#0      ListTile.debugCheck (package:flutter/src/material/list_tile.dart:900:7)
#1      RenderObject.paint (package:flutter/src/rendering/object.dart:3000:5)
''');

void main() {
  late List<String> printed;
  late FlutterExceptionHandler? savedOnError;
  late FlutterExceptionHandler savedPresent;
  late ErrorCallback? savedPlatform;

  setUp(() {
    printed = [];
    savedOnError = FlutterError.onError;
    savedPresent = FlutterError.presentError;
    savedPlatform = PlatformDispatcher.instance.onError;
    // What a running app starts with (the test runner may install its own).
    FlutterError.onError = FlutterError.dumpErrorToConsole;
    TidyLog.reset();
    TidyLog.configure(enabled: true, color: false, printer: printed.add);
  });

  tearDown(() {
    FlutterError.onError = savedOnError;
    FlutterError.presentError = savedPresent;
    PlatformDispatcher.instance.onError = savedPlatform;
    TidyLog.reset();
  });

  test('a crash reporter installed after the hooks gets every error, and the box is replaced', () {
    TidyLog.installErrorHooks();
    // How Sentry and similar reporters wrap the handler they find.
    final reported = <FlutterErrorDetails>[];
    final original = FlutterError.onError;
    FlutterError.onError = (d) {
      reported.add(d);
      original?.call(d);
    };

    FlutterError.reportError(_details('Bad state: no user\nMore detail here.'));

    expect(reported, hasLength(1));
    expect(printed.first, startsWith('ERR Bad state: no user'));
    expect(printed, contains('    More detail here.'));
    expect(printed.join('\n'), isNot(contains('EXCEPTION CAUGHT')));
  });

  test('a handler set before the hooks is kept, and a hint says to install the hooks first', () {
    final reported = <FlutterErrorDetails>[];
    void reporter(FlutterErrorDetails d) => reported.add(d);
    FlutterError.onError = reporter;

    TidyLog.installErrorHooks();
    FlutterError.reportError(_details('Bad state: no user'));

    expect(FlutterError.onError, same(reporter));
    expect(reported, hasLength(1));
    expect(printed.single, startsWith('WRN FlutterError.onError was already set.'));
  });

  test('the same error again prints one short "thrown again" line', () {
    TidyLog.installErrorHooks();
    FlutterError.reportError(_details('ListTile background color may be invisible.'));
    final firstCount = printed.length;
    FlutterError.reportError(_details('ListTile background color may be invisible.'));

    expect(printed.length, firstCount + 1);
    expect(printed.last, startsWith('ERR ListTile background color may be invisible.'));
    expect(printed.last, endsWith('· thrown again'));
  });

  test('uses the error-causing widget location when the stack has no frame of yours', () {
    TidyLog.installErrorHooks();
    FlutterError.reportError(
      _details(
        'ListTile background color may be invisible.',
        stack: _frameworkStack,
        info: () => [
          ErrorDescription('The relevant error-causing widget was:'),
          ErrorDescription('  ListTile ListTile:file:///Users/me/app/lib/app/view/settings_page.dart:88:16'),
        ],
      ),
    );
    expect(printed, contains('    at lib/app/view/settings_page.dart:88:16  ListTile'));
  });

  test('the hooks survive the widget inspector swapping presentError afterwards', () {
    TidyLog.installErrorHooks();
    // What WidgetInspectorService.initServiceExtensions does in every debug
    // run once the binding starts (structured errors for the IDE).
    final structured = <FlutterErrorDetails>[];
    FlutterError.presentError = structured.add;

    FlutterError.reportError(_details('A RenderFlex overflowed by 268 pixels on the right.'));

    expect(printed.first, startsWith('ERR A RenderFlex overflowed by 268 pixels on the right.'));
    expect(structured, isEmpty, reason: 'the tidy formatter prints it, not the inspector');
  });

  test('keepStructuredErrors: true leaves the error to presentError, as before', () {
    TidyLog.installErrorHooks(keepStructuredErrors: true);
    final structured = <FlutterErrorDetails>[];
    FlutterError.presentError = structured.add;

    FlutterError.reportError(_details('A RenderFlex overflowed by 268 pixels on the right.'));

    expect(structured, hasLength(1));
    expect(printed, isEmpty);
  });

  test('uncaught async errors are logged and the previous handler decides', () {
    final seen = <Object>[];
    PlatformDispatcher.instance.onError = (error, stack) {
      seen.add(error);
      return false;
    };
    TidyLog.installErrorHooks();

    final handled = PlatformDispatcher.instance.onError!(StateError('late'), StackTrace.empty);

    expect(handled, isFalse, reason: 'the previous handler returned false');
    expect(seen, hasLength(1));
    expect(printed.first, startsWith('ERR Bad state: late'));
  });

  test('with no previous async handler the error counts as handled', () {
    PlatformDispatcher.instance.onError = null;
    TidyLog.installErrorHooks();
    expect(PlatformDispatcher.instance.onError!(StateError('late'), StackTrace.empty), isTrue);
  });

  group('when the logger is off', () {
    test('enabled: false leaves every handler as it was', () {
      TidyLog.configure(enabled: false);
      final onError = FlutterError.onError;
      final present = FlutterError.presentError;
      bool platform(Object error, StackTrace stack) => false;
      PlatformDispatcher.instance.onError = platform;

      TidyLog.installErrorHooks();

      expect(FlutterError.onError, same(onError));
      expect(FlutterError.presentError, same(present));
      expect(PlatformDispatcher.instance.onError, same(platform));
    });

    test('disabled after the hooks are installed, errors go to the handlers they replaced', () {
      final presented = <FlutterErrorDetails>[];
      FlutterError.presentError = presented.add;
      PlatformDispatcher.instance.onError = null;
      TidyLog.installErrorHooks();
      TidyLog.configure(enabled: false);

      FlutterError.reportError(_details('Bad state: no user'));
      final handled = PlatformDispatcher.instance.onError!(StateError('late'), StackTrace.empty);

      expect(presented, hasLength(1), reason: "Flutter's own presenter prints it");
      expect(handled, isFalse, reason: 'the engine reports the unhandled error itself');
      expect(printed, isEmpty);
    });

    test('an uncaught error below minLevel is not marked handled', () {
      PlatformDispatcher.instance.onError = null;
      TidyLog.configure(minLevel: Level.fatal);
      TidyLog.installErrorHooks();
      expect(PlatformDispatcher.instance.onError!(StateError('late'), StackTrace.empty), isFalse);
      expect(printed, isEmpty);
    });
  });

  test('an uncaught error that fails to log still reaches the previous handler', () {
    final savedDebugPrint = debugPrint;
    addTearDown(() => debugPrint = savedDebugPrint);
    debugPrint = (message, {wrapWidth}) {};
    final seen = <Object>[];
    PlatformDispatcher.instance.onError = (error, stack) {
      seen.add(error);
      return true;
    };
    TidyLog.configure(printer: (line) => throw StateError('printer bug'));
    TidyLog.installErrorHooks();

    expect(PlatformDispatcher.instance.onError!(StateError('late'), StackTrace.empty), isTrue);
    expect(seen, hasLength(1));
  });

  group('installErrorHooks called twice', () {
    test('logs an uncaught error once and calls the previous handler once', () {
      var calls = 0;
      PlatformDispatcher.instance.onError = (error, stack) {
        calls++;
        return true;
      };
      TidyLog.installErrorHooks();
      TidyLog.installErrorHooks();

      PlatformDispatcher.instance.onError!(StateError('late'), StackTrace.empty);

      expect(printed.where((l) => l.startsWith('ERR Bad state: late')), hasLength(1));
      expect(calls, 1);
    });

    test('with keepStructuredErrors: true prints no "already set" hint', () {
      TidyLog.installErrorHooks(keepStructuredErrors: true);
      TidyLog.installErrorHooks(keepStructuredErrors: true);
      expect(printed, isEmpty);
    });

    test('with different options prints one hint and keeps the first setup', () {
      TidyLog.installErrorHooks();
      TidyLog.installErrorHooks(keepStructuredErrors: true);
      expect(printed.single, startsWith('WRN installErrorHooks() was already called'));

      final structured = <FlutterErrorDetails>[];
      FlutterError.presentError = structured.add;
      FlutterError.reportError(_details('Bad state: no user'));
      expect(structured, isEmpty, reason: 'the first call routes errors to the tidy formatter');
    });
  });
}
