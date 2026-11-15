import 'package:test/test.dart';
import 'package:tidy_log_core/tidy_log_core.dart';

void main() {
  group('parseJavaStack', () {
    // The stack the Android embedding sends back inside a PlatformException
    // when a method-call handler throws (captured from sample_app).
    const handlerThrow = '''
java.lang.IllegalStateException: Keystore entry missing
	at dev.tidylog.tidy_log_sample.MainActivity.configureFlutterEngine\$lambda\$0(MainActivity.kt:35)
	at io.flutter.plugin.common.MethodChannel\$IncomingMethodCallHandler.onMessage(MethodChannel.java:267)
	at android.os.Looper.loop(Looper.java:397)
Caused by: java.io.IOException: decryption failed
	... 3 more''';

    test('picks the exception, the first app frame and the last cause', () {
      final stack = parseJavaStack(handlerThrow.split('\n'))!;

      expect(stack.exception, 'IllegalStateException: Keystore entry missing');
      expect(stack.frame, r'dev.tidylog.tidy_log_sample.MainActivity.configureFlutterEngine$lambda$0(MainActivity.kt:35)');
      expect(stack.frameCount, 3);
      expect(stack.cause, 'IOException: decryption failed');
      expect(stack.note, '… 2 frames hidden · caused by IOException: decryption failed');
    });

    test('falls back to the top frame when every frame is SDK code', () {
      final stack = parseJavaStack(['java.lang.NullPointerException', '  at android.os.Handler.handleCallback(Handler.java:1095)'])!;
      expect(stack.frame, 'android.os.Handler.handleCallback(Handler.java:1095)');
      expect(stack.note, isEmpty, reason: 'one frame, no cause');
    });

    test('is null for text that has no frames', () {
      expect(parseJavaStack(['Card reader is not connected.']), isNull);
    });
  });

  test('shortJavaException drops the package and a trailing colon', () {
    expect(shortJavaException('android.os.RemoteException: Remote stack trace:'), 'RemoteException: Remote stack trace');
    expect(shortJavaException('not an exception'), 'not an exception');
  });

  group('Flutter follow-on errors', () {
    test('stripRenderIds removes ids, relayout boundaries and dirty flags', () {
      expect(
        stripRenderIds('RenderBox was not laid out: RenderIgnorePointer#4907d relayoutBoundary=up10 NEEDS-PAINT NEEDS-COMPOSITING-BITS-UPDATE'),
        'RenderBox was not laid out: RenderIgnorePointer',
      );
      expect(stripRenderIds('RenderViewport#0c59b NEEDS-PAINT'), 'RenderViewport');
      expect(stripRenderIds('A RenderFlex overflowed by 268 pixels on the right.'), 'A RenderFlex overflowed by 268 pixels on the right.');
    });

    test('isFollowOnError matches side-effect errors only', () {
      expect(isFollowOnError('RenderBox was not laid out: RenderViewport'), isTrue);
      expect(isFollowOnError('Cannot hit test a render box that has never been laid out.'), isTrue);
      expect(isFollowOnError('Vertical viewport was given unbounded height.'), isFalse);
      expect(followOnKind('RenderBox was not laid out: RenderFlex'), 'RenderBox was not laid out');
    });
  });
}
