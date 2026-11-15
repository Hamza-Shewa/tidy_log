import 'package:test/test.dart';
import 'package:tidy_log_core/src/console/logcat_line.dart';
import 'package:tidy_log_core/src/console/noise_filter.dart';
import 'package:tidy_log_core/tidy_log_core.dart';

bool shows(NoiseFilter f, String line) => f.shows(LogcatLine.tryParse(line)!);

void main() {
  test('quiet preset hides chatter tags, wildcard tags and avc lines, but keeps errors from other tags', () {
    final quiet = NoiseFilter(TidyConfig());
    expect(shows(quiet, 'D/WindowOnBackDispatcher(1): setTopOnBackInvokedCallback'), isFalse);
    expect(shows(quiet, 'I/cr_PolicyProvider(1): #notifySettingsAvailable() 0'), isFalse);
    expect(shows(quiet, 'D/VRI[MainActivity](1): visibilityChanged'), isFalse);
    expect(shows(quiet, 'W/com.example.wallet(1): type=1400 audit(0.0:110): avc:  granted  { execute }'), isFalse);
    expect(shows(quiet, 'E/FlutterSecureStorage(1): decryption failed'), isTrue);
    expect(shows(quiet, 'D/FlutterJNI(1): Sending viewport metrics to the engine.'), isTrue);
  });

  test('all preset shows the same chatter', () {
    final all = NoiseFilter(TidyConfig(preset: Preset.all));
    expect(shows(all, 'D/WindowOnBackDispatcher(1): setTopOnBackInvokedCallback'), isTrue);
    expect(shows(all, 'W/x(1): avc:  denied  { read }'), isTrue);
  });

  test('show_tags overrides the preset and hide_tags adds to it', () {
    final custom = NoiseFilter(TidyConfig(showTags: const ['ImeTracker'], hideTags: const ['FlutterJNI']));
    expect(shows(custom, 'I/ImeTracker(1): onShown'), isTrue);
    expect(shows(custom, 'D/FlutterJNI(1): Sending viewport metrics to the engine.'), isFalse);
  });

  test('min_native_level drops lower native levels but never Dart lines', () {
    final warnings = NoiseFilter(TidyConfig(minNativeLevel: Level.warning));
    expect(shows(warnings, 'I/FlutterGeolocator(1): Creating service.'), isFalse);
    expect(shows(warnings, 'W/FlutterDefender(1): failed'), isTrue);
    expect(shows(warnings, 'I/flutter (1): ar_LY'), isTrue);
  });
}
