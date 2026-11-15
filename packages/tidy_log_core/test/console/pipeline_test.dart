import 'package:test/test.dart';
import 'package:tidy_log_core/tidy_log_core.dart';

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
    final out = squash(clean([for (var i = 0; i < 30; i++) 'D/FlutterJNI(7): Sending viewport metrics to the engine.']));
    expect(out.last, 'DBG Sending viewport metrics to the engine.  · FlutterJNI  ×30');
    expect(out, hasLength(2));
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
      'POST /api/Auth/Signin  10.0.0.1:4013  401  1,003 ms · 15:21:09',
      '    body  {userId: 1, pin: ••••••••, authUserType: 0}',
      '    resp  {"error":"bad pin"}',
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
    final out = squash(clean([
      'I/flutter (100): first',
      'I/flutter (200): second',
      'W/System.err(100): late line from the old process',
    ]));
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
    expect(clean(['I/flutter (1): Svg loader: unhandled element'], config: config).last, 'SVG Svg loader: unhandled element');
  });
}
