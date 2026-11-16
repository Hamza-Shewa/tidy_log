import 'package:flutter_test/flutter_test.dart';
import 'package:tidy_log/src/core.dart';

import '../helpers.dart';

void main() {
  test('moves the native prefix to a suffix and labels the level', () {
    expect(squash(clean(['E/FlutterSecureStorage(31800): Falling back to custom ciphers.'])), [
      '──────── app started · pid 31800 ────────',
      'ERR Falling back to custom ciphers.  · FlutterSecureStorage',
    ]);
  });

  test('Dart lines lose the I/flutter prefix and get no suffix', () {
    expect(clean(['I/flutter (1): ar_LY']).last, '    ar_LY');
  });

  test('collapses a run of identical native lines into one line with ×N', () {
    final out = squash(
      clean([for (var i = 0; i < 30; i++) 'D/FlutterJNI(7): Sending viewport metrics to the engine.']),
    );
    expect(out.last, 'DBG Sending viewport metrics to the engine.  · FlutterJNI  ×30');
    expect(out, hasLength(2));
  });

  test('follow-on layout errors after the root error fold into one line, without render ids', () {
    final out = squash(
      clean([
        'Another exception was thrown: Vertical viewport was given unbounded height.',
        'Another exception was thrown: RenderBox was not laid out: RenderViewport#0c59b NEEDS-LAYOUT NEEDS-PAINT',
        'Another exception was thrown: RenderBox was not laid out: RenderIgnorePointer#4907d relayoutBoundary=up10 NEEDS-PAINT',
        'Another exception was thrown: RenderBox was not laid out: RenderFlex#96b54 relayoutBoundary=up1 NEEDS-PAINT',
        'I/flutter (1): >>> next',
      ]),
    );
    expect(out, [
      'ERR Vertical viewport was given unbounded height.  · thrown again',
      'ERR RenderBox was not laid out: RenderViewport  · thrown again',
      '    ↳ +2 similar',
      '──────── app started · pid 1 ────────',
      '    >>> next',
    ]);
  });

  test('folds a Java trace to the exception, the first non-SDK frame and a summary', () {
    final out = clean([
      'W/FlutterDefender(9): Screen-capture callback registration failed.',
      'W/FlutterDefender(9): java.lang.SecurityException: Permission Denial',
      'W/FlutterDefender(9):       at android.os.Parcel.readException(Parcel.java:3334)',
      'W/FlutterDefender(9):       at com.example.defender.Plugin.register(Plugin.kt:308)',
      'W/FlutterDefender(9):       at android.app.ActivityThread.main(ActivityThread.java:9569)',
      'W/FlutterDefender(9): Caused by: android.os.RemoteException: Remote stack trace:',
      'W/FlutterDefender(9):       at com.android.server.X.y(X.java:1)',
    ]).skip(1).toList();
    expect(squash(out), [
      'WRN Screen-capture callback registration failed.  · FlutterDefender',
      '    SecurityException: Permission Denial',
      '    at com.example.defender.Plugin.register(Plugin.kt:308)',
      '    ┊ … 3 frames hidden · caused by RemoteException: Remote stack trace',
    ]);
  });

  test('a printed Dart trace leads with the first project frame and drops async gaps', () {
    final out = clean([
      'I/flutter (5): Error refreshing session: bad sign',
      'I/flutter (5): #0      Http.send (package:dio/src/dio.dart:10:1)',
      'I/flutter (5): #1      Repo.refresh (package:core_kit/data/repo.dart:37:24)',
      'I/flutter (5): <asynchronous suspension>',
      'I/flutter (5): #2      HomePage.build (package:app/app/view/home_page.dart:145:12)',
    ]).skip(1).toList();
    expect(out, [
      'ERR Error refreshing session: bad sign',
      '    at package:core_kit/data/repo.dart:37:24  Repo.refresh',
      '    ┊ lib/app/view/home_page.dart:145:12  HomePage.build',
      '    ┊ … 1 frame hidden',
    ]);
  });

  test('restyles a Dio box and masks the PIN', () {
    final out = clean([
      'I/flutter (3): ┌------',
      'I/flutter (3): | [DIO] Request: POST http://10.0.0.1:4013/api/Auth/Signin',
      'I/flutter (3): | Time: 2026-11-15 15:21:09.634373',
      'I/flutter (3): | {userId: 1, pin: 12345678, authUserType: 0}',
      'I/flutter (3): | Headers:',
      'I/flutter (3): | authorization: | content-type: application/json',
      'I/flutter (3): ├------',
      'I/flutter (3): | [DIO] Response [code 401]: {"error":"bad pin"}',
      'I/flutter (3): | [DIO] Duration: 1003ms',
      'I/flutter (3): └------',
    ]).skip(1).toList();
    expect(out, [
      '${'POST'.padRight(7)}${'/api/Auth/Signin'.padRight(46)}  401  ${'1,003 ms'.padLeft(9)}  15:21:09  10.0.0.1:4013',
      '    body  userId: 1',
      '          pin: ••••••••',
      '          authUserType: 0',
      '    resp  error: bad pin',
    ]);
  });

  test('route observer lines become NAV lines', () {
    final out = clean([
      'I/flutter (1): from /root Pushed route: /login',
      'I/flutter (1): from /login Popped route: /otp',
    ]).skip(1).toList();
    expect(out, ['NAV /root → /login', 'NAV back /otp → /login']);
  });

  test('folds a framework error box and counts "Another exception was thrown"', () {
    final out = clean([
      '══╡ EXCEPTION CAUGHT BY WIDGETS LIBRARY ╞═══════════════════════',
      'The following assertion was thrown building HomePage:',
      'Bad state: no user',
      '',
      'The relevant error-causing widget was:',
      '  HomePage HomePage:file:///Users/me/app/lib/app/view/home_page.dart:145:12',
      '═══════════════════════════════════════════════════════════════',
      'Another exception was thrown: Bad state: no user',
      'Another exception was thrown: Bad state: no user',
    ]);
    expect(squash(out), [
      'ERR Bad state: no user  · caught by widgets library',
      '    at lib/app/view/home_page.dart:145:12  HomePage',
      'ERR Bad state: no user  · thrown again  ×2',
    ]);
  });

  test('marks a new process with a divider and tags lines from the old one', () {
    final out = squash(
      clean(['I/flutter (100): first', 'I/flutter (200): second', 'W/System.err(100): late line from the old process']),
    );
    expect(out, [
      '──────── app started · pid 100 ────────',
      '    first',
      '──────── app started · pid 200 ────────',
      '    second',
      'WRN late line from the old process  · System.err · pid 100',
    ]);
  });

  test('hot restart output becomes a divider', () {
    expect(clean(['Restarted application in 1,603ms.']), ['──────── hot restart · 1,603 ms ────────']);
    expect(clean(['Reloaded 0 libraries in 271ms (compile: 15 ms, reload: 0 ms, reassemble: 141 ms).']), [
      '──────── hot reload · 271 ms ────────',
    ]);
    expect(clean(['Reloaded 1 of 812 libraries in 310ms.']), ['──────── hot reload · 310 ms ────────']);
  });

  test('custom rules label matching Dart lines', () {
    final config = TidyConfig.fromYaml('rules:\n  - match: "^Svg"\n    label: SVG\n    tone: warning\n');
    expect(
      clean(['I/flutter (1): Svg loader: unhandled element'], config: config).last,
      'SVG Svg loader: unhandled element',
    );
  });

  group('coloured lines', () {
    const styled = Renderer(includeSource: false);
    const plainCopy = Renderer(color: false);
    String only(List<String> out) => out.where((l) => !l.contains('app started')).single;

    for (final (name, line) in [
      ('a logger-style line', 'I/flutter (1): \x1B[38;5;12mpassword: hunter2\x1B[0m'),
      ('a colour code right before the key', 'I/flutter (1): \x1B[33mtoken=hunter2\x1B[0m'),
      ('a line without the logcat prefix', '\x1B[31mpassword: hunter2\x1B[0m'),
    ]) {
      test('$name from another logging package is redacted in the console and in the plain copy', () {
        final console = only(clean([line], renderer: styled));
        final copy = only(clean([line], renderer: plainCopy));
        expect(console, isNot(contains('hunter2')));
        expect(console, contains('••••••••\x1B[0m'), reason: 'colours are kept, the reset outside the mask');
        expect(copy, isNot(contains('hunter2')));
        expect(copy, isNot(contains('\x1B[')));
        expect(copy, endsWith('••••••••'));
      });
    }

    test("TidyLog's own lines (starting with a reset) pass through as printed", () {
      const line = '\x1B[0m\x1B[90msecret: already redacted in the app\x1B[0m';
      expect(only(clean(['I/flutter (1): $line'], renderer: styled)), line);
    });
  });

  group('a pretty_dio_logger box that is split', () {
    const p = 'I/flutter (1): ';
    final rule = '╚${'═' * 40}╝';
    List<String> response(List<String> body) => [
      '$p╔╣ Response ║ GET ║ Status: 200 OK',
      '$p║  http://h/api/session',
      '$p$rule',
      '$p╔ Body',
      '$p║',
      '$p║    {',
      ...body,
      '$p║    }',
      '$p$rule',
    ];
    List<String> render(List<Entry> entries) => [for (final e in entries) ...plain.render(e)];

    test('a native line inside the box neither splits it nor spills the wrapped token', () {
      final out = clean(
        response([
          '$p║         sessionKey: "abc123def456ghi789jkl',
          'W/MyPlugin(1): plugin warning',
          '$p║         mno345pqr678stu901vwx",',
          '$p║         userId: 7',
        ]),
        config: TidyConfig(redactKeys: const ['sessionkey']),
      );
      final all = out.join('\n');
      expect(all, isNot(contains('jkl')));
      expect(all, isNot(contains('mno345')));
      expect(all, contains('sessionKey: ••••••••'));
      expect(all, contains('userId: 7'));
      expect(all, contains('plugin warning'));
      expect(all, isNot(contains('║')));
    });

    test('an idle flush in the middle of a box waits for the rest of it', () {
      final pipeline = ConsolePipeline(TidyConfig());
      final lines = response([
        '$p║         note: "eyJhbGciOiJIUzI1NiJ9.eyJzdWIi',
        '$p║         OiIxMjM0NTY3ODkwIn0.dozjgNryP4J3',
        '$p║         jVmNHl0w5N_XgL0n3I9PlFUP0THsR8U"',
      ]);
      final first = [for (final l in lines.take(7)) ...pipeline.add(l), ...pipeline.flush()];
      expect(render(first).where((l) => !l.startsWith('────')), isEmpty);
      expect(pipeline.holdsPartialBox, isTrue);
      final rest = [for (final l in lines.skip(7)) ...pipeline.add(l), ...pipeline.flush()];
      final all = render([...first, ...rest]).join('\n');
      expect(all, isNot(contains('OiIxMjM0')));
      expect(all, isNot(contains('jVmNHl0w5N')));
      expect(all, contains('GET    /api/session'));
      expect(pipeline.holdsPartialBox, isFalse);
    });

    test('a box that waited too long is closed, and its late lines are counted, not printed', () {
      var now = DateTime(2026);
      final pipeline = ConsolePipeline(TidyConfig(), clock: () => now);
      final lines = response([
        '$p║         note: "eyJhbGciOiJIUzI1NiJ9.eyJzdWIi',
        '$p║         OiIxMjM0NTY3ODkwIn0.dozjgNryP4J3',
        '$p║         jVmNHl0w5N_XgL0n3I9PlFUP0THsR8U"',
      ]);
      final first = [for (final l in lines.take(7)) ...pipeline.add(l)];
      now = now.add(const Duration(seconds: 3));
      first.addAll(pipeline.flush());
      expect(render(first).join('\n'), contains('GET    /api/session'));
      final rest = render([for (final l in lines.skip(7)) ...pipeline.add(l), ...pipeline.flush()]);
      expect(rest, ['    ┊ … 4 more HTTP box lines not shown']);
      final all = render(first).join('\n');
      expect(all, isNot(contains('eyJzdWIi')));
    });

    test('a 600-line body is read up to the cap; the rest is counted, not printed raw', () {
      final pipeline = ConsolePipeline(TidyConfig());
      final lines = response([for (var i = 0; i < 600; i++) '$p║         id: $i,']);
      final out = render([for (final l in lines) ...pipeline.add(l), ...pipeline.finish()]);
      expect(out.where((l) => l.contains('║') || l.contains('id: 599')), isEmpty);
      expect(out.where((l) => l.startsWith('GET ')), hasLength(1));
      expect(out.last, matches(RegExp(r'^    ┊ … \d+ more HTTP box lines not shown$')));
      expect(out.length, lessThan(25));
    });
  });

  test('a URL that does not decode to UTF-8 is shown as printed instead of throwing', () {
    const p = 'I/flutter (1): ';
    final rule = '╚${'═' * 40}╝';
    final out = clean([
      '$p╔╣ Request ║ GET ',
      '$p║  http://h/api/user?name=Jos%E9',
      '$p$rule',
      '$p╔╣ Response ║ GET ║ Status: 200 OK',
      '$p║  http://h/api/user?name=Jos%E9',
      '$p$rule',
    ]);
    expect(out.where((l) => l.startsWith('GET ')).single, startsWith('GET    /api/user?name=Jos%E9 '));
  });
}
