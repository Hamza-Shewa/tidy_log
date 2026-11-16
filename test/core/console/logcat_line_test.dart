import 'package:flutter_test/flutter_test.dart';
import 'package:tidy_log/src/core/console/logcat_line.dart';
import 'package:tidy_log/src/core.dart';

void main() {
  group('LogcatLine.tryParse', () {
    test('reads level, tag, pid and message', () {
      final line = LogcatLine.tryParse('E/FlutterSecureStorage(31800): Falling back to custom ciphers.')!;
      expect(line.level, Level.error);
      expect(line.tag, 'FlutterSecureStorage');
      expect(line.pid, 31800);
      expect(line.message, 'Falling back to custom ciphers.');
      expect(line.isDart, isFalse);
    });

    test('handles padded tags and pids', () {
      final padded = LogcatLine.tryParse('W/System  (31131): A resource failed to call ZipFile.close. ')!;
      expect(padded.tag, 'System');
      expect(padded.pid, 31131);
      final dart = LogcatLine.tryParse('I/flutter ( 2287): ar_LY')!;
      expect((dart.tag, dart.pid, dart.isDart), ('flutter', 2287, true));
    });

    test('keeps tags with dots and brackets', () {
      expect(LogcatLine.tryParse('W/System.err(31131): boom')!.tag, 'System.err');
      expect(LogcatLine.tryParse('D/VRI[MainActivity](31131): visibilityChanged')!.tag, 'VRI[MainActivity]');
    });

    test('keeps leading whitespace after the single separator space', () {
      expect(LogcatLine.tryParse('W/System.err(31131):    at java.net.X(X.java:1)')!.message, '   at java.net.X(X.java:1)');
      expect(LogcatLine.tryParse('W/FlutterDefender(31800): ')!.message, '');
    });

    test('returns null for tool output', () {
      expect(LogcatLine.tryParse('Syncing files to device sdk gphone16k arm64...   192ms'), isNull);
      expect(LogcatLine.tryParse('Another exception was thrown: x'), isNull);
      expect(LogcatLine.tryParse(''), isNull);
    });
  });
}
