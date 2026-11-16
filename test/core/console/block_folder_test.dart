import 'package:flutter_test/flutter_test.dart';
import 'package:tidy_log/src/core/console/block_folder.dart';
import 'package:tidy_log/src/core/console/logcat_line.dart';

List<List<String>> fold(List<String> lines) {
  final folder = BlockFolder();
  final blocks = [for (final l in lines) ...folder.add(LogcatLine.tryParse(l)!), ...folder.flush()];
  return [for (final b in blocks) b.messages];
}

void main() {
  test('keeps a Java exception, its frames, Caused by and "... N more" in one block', () {
    final blocks = fold([
      'E/FlutterSecureStorage(31800): EncryptedSharedPreferences initialization failed.',
      'E/FlutterSecureStorage(31800): java.lang.SecurityException: Could not decrypt key.',
      'E/FlutterSecureStorage(31800):  at com.a.B.c(B.java:561)',
      'E/FlutterSecureStorage(31800): Caused by: java.security.GeneralSecurityException: decryption failed',
      'E/FlutterSecureStorage(31800):  ... 15 more',
      'D/FlutterJNI(31800): Sending viewport metrics to the engine.',
    ]);
    expect(blocks, hasLength(2));
    expect(blocks.first, hasLength(5));
    expect(blocks.first.last, ' ... 15 more');
    expect(blocks.last, ['Sending viewport metrics to the engine.']);
  });

  test('starts a new block for a second exception that follows frames', () {
    final blocks = fold([
      'W/System.err(31131): java.net.SocketException: Unresolved address',
      'W/System.err(31131):    at java.net.DatagramSocket.connect(DatagramSocket.java:518)',
      'W/System.err(31131): java.net.SocketException: Unresolved address',
      'W/System.err(31131):    at java.net.DatagramSocket.connect(DatagramSocket.java:518)',
    ]);
    expect(blocks.map((b) => b.length), [2, 2]);
  });

  test('a line from another tag or pid closes the block', () {
    final blocks = fold([
      'W/FlutterDefender(31800): failed',
      'W/FlutterDefender(31131):       at a.B.c(B.java:1)',
      'W/Other(31800):       at a.B.c(B.java:1)',
    ]);
    expect(blocks.map((b) => b.length), [1, 1, 1]);
  });

  test('a Dio box stays one block from ┌ to └, then closes on its own', () {
    final folder = BlockFolder();
    final closed = [
      for (final l in [
        'I/flutter (32287): ┌-----',
        'I/flutter (32287): | [DIO] Request: POST http://h/x',
        'I/flutter (32287): ├-----',
        'I/flutter (32287): └-----',
      ])
        ...folder.add(LogcatLine.tryParse(l)!),
    ];
    expect(closed.single.messages, hasLength(4));
    expect(folder.flush(), isEmpty);
  });

  test('Dart frames and async gaps join the line before them', () {
    final blocks = fold([
      'I/flutter (32287): Error refreshing session: bad sign',
      'I/flutter (32287): #0      A.b (package:core_kit/a.dart:42:5)',
      'I/flutter (32287): <asynchronous suspension>',
      'I/flutter (32287): ar_LY',
    ]);
    expect(blocks.map((b) => b.length), [3, 1]);
  });

  test('a line the in-app logger already styled never takes continuations', () {
    final blocks = fold([
      'I/flutter (1): \x1B[0mERR boom',
      'I/flutter (1): \x1B[0m    at lib/a.dart:1:1',
      'I/flutter (1):    indented plain text',
    ]);
    expect(blocks.map((b) => b.length), [1, 1, 1]);
  });
}
