import 'package:flutter/services.dart';

/// The Dart side of the method channel set up in `MainActivity.kt`.
final class NativeBridge {
  const NativeBridge({
    this.channel = const MethodChannel('tidy_log_sample/native'),
    this.unregistered = const MethodChannel('tidy_log_sample/not_registered'),
  });

  /// Registered on Android: answers, fails, throws or says "not implemented".
  final MethodChannel channel;

  /// Never registered on the native side, like a plugin that was not linked.
  final MethodChannel unregistered;

  /// Succeeds with the battery percentage.
  Future<int?> batteryLevel() => channel.invokeMethod<int>('getBatteryLevel');

  /// Native replies with `result.error("UNAVAILABLE", …)`.
  Future<void> readCard() => channel.invokeMethod<void>('failWithPlatformError');

  /// Native throws inside its handler; the engine logs the Java stack and
  /// returns it to Dart inside a PlatformException.
  Future<void> openKeystore() => channel.invokeMethod<void>('throwInHandler');

  /// Native replies `result.notImplemented()`.
  Future<void> scanFingerprint() => channel.invokeMethod<void>('scanFingerprint');

  /// No handler at all on this channel.
  Future<void> pingMissingPlugin() => unregistered.invokeMethod<void>('ping');

  /// Native writes logcat lines at each level, a stack trace and repeats.
  Future<void> emitNativeLogs() => channel.invokeMethod<void>('emitNativeLogs');
}

/// The shape of a federated plugin's platform interface: the default
/// implementation throws until a platform registers one.
abstract base class BiometricsPlatform {
  Future<bool> authenticate() => throw UnimplementedError('authenticate() has not been implemented.');
}

/// What you get when no platform package registered an implementation.
final class DefaultBiometrics extends BiometricsPlatform {}
