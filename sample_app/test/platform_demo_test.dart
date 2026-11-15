import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tidy_log_sample/demos/platform_demo.dart';
import 'package:tidy_log_sample/platform/native_bridge.dart';

import 'helpers.dart';

/// The Android handler is not available in unit tests, so these stand in
/// for it with a mock handler that answers the way `MainActivity.kt` does.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const bridge = NativeBridge();
  late RecordingLogger logger;
  late PlatformDemo demo;

  setUp(() {
    logger = RecordingLogger();
    demo = PlatformDemo(bridge, DefaultBiometrics(), logger);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(bridge.channel, (call) async {
      switch (call.method) {
        case 'getBatteryLevel':
          return 87;
        case 'failWithPlatformError':
          throw PlatformException(code: 'UNAVAILABLE', message: 'Card reader is not connected.');
        case 'emitNativeLogs':
          return null;
      }
      throw MissingPluginException();
    });
  });

  tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(bridge.channel, null));

  test('a successful call logs the battery level', () async {
    expect(await demo.batteryLevel(), 'Battery at 87%');
    expect(logger.records.single, (level: 'i', message: 'Battery at 87%', tag: 'Native', error: null, stackTrace: null));
  });

  test('an error reply is caught and logged with its code', () async {
    expect(await demo.readCard(), 'Card reader failed: UNAVAILABLE');
    expect(logger.records.single.error, isA<PlatformException>().having((e) => e.message, 'message', 'Card reader is not connected.'));
  });

  test('a native exception arrives as a PlatformException with the Java stack', () async {
    // The Android embedding replies with a four-field error envelope; the
    // mock method handler cannot send the fourth (stacktrace) field.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler(bridge.channel.name, (_) async {
      const codec = StandardMessageCodec();
      final buffer = WriteBuffer()..putUint8(1);
      for (final value in ['error', 'Keystore entry missing', null, 'java.lang.IllegalStateException: Keystore entry missing']) {
        codec.writeValue(buffer, value);
      }
      return buffer.done();
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler(bridge.channel.name, null));

    expect(await demo.openKeystore(), 'Keystore failed: error');
    expect((logger.records.single.error! as PlatformException).stacktrace, startsWith('java.lang.IllegalStateException'));
  });

  test('notImplemented and a missing plugin are left uncaught as MissingPluginException', () async {
    await expectLater(demo.scanFingerprint(), throwsA(isA<MissingPluginException>()));
    await expectLater(demo.pingMissingPlugin(), throwsA(isA<MissingPluginException>()));
    expect(logger.records, isEmpty);
  });

  test('an unimplemented platform interface throws before returning a Future', () {
    expect(
      demo.authenticate,
      throwsA(isA<UnimplementedError>().having((e) => e.message, 'message', 'authenticate() has not been implemented.')),
    );
  });
}
