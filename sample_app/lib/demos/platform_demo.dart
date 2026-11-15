import 'package:flutter/services.dart';

import '../logging/app_logger.dart';
import '../platform/native_bridge.dart';

/// Platform-channel calls that succeed, fail, or are missing on the
/// native side.
final class PlatformDemo {
  const PlatformDemo(this._bridge, this._biometrics, this._logger);

  final NativeBridge _bridge;
  final BiometricsPlatform _biometrics;
  final AppLogger _logger;

  static const _tag = 'Native';

  Future<String> batteryLevel() async {
    final level = await _bridge.batteryLevel();
    _logger.i('Battery at $level%', tag: _tag);
    return 'Battery at $level%';
  }

  /// Native replies with an error code: caught and logged.
  Future<String> readCard() => _caught('Card reader', _bridge.readCard);

  /// Native throws in its handler: caught and logged. The Java stack trace
  /// travels inside the PlatformException.
  Future<String> openKeystore() => _caught('Keystore', _bridge.openKeystore);

  /// `result.notImplemented()` becomes a MissingPluginException. Left
  /// uncaught, like a call to a plugin method that one platform lacks.
  Future<String> scanFingerprint() async {
    await _bridge.scanFingerprint();
    return 'Fingerprint scanned';
  }

  /// No handler on the channel at all. Left uncaught.
  Future<String> pingMissingPlugin() async {
    await _bridge.pingMissingPlugin();
    return 'Plugin answered';
  }

  /// A platform interface with no implementation registered: throws
  /// `UnimplementedError` synchronously, before any Future exists.
  Future<String> authenticate() => _biometrics.authenticate().then((ok) => ok ? 'Authenticated' : 'Not authenticated');

  Future<String> nativeLogs() async {
    await _bridge.emitNativeLogs();
    return 'Native side wrote its logcat lines';
  }

  Future<String> _caught(String what, Future<void> Function() call) async {
    try {
      await call();
      return '$what unexpectedly succeeded';
    } on PlatformException catch (error, stack) {
      _logger.e('$what failed: ${error.code}', tag: _tag, error: error, stackTrace: stack);
      return '$what failed: ${error.code}';
    }
  }
}
