import 'package:flutter_test/flutter_test.dart';
import 'package:tidy_log/src/core/console/logcat_line.dart';
import 'package:tidy_log/src/core/console/noise_filter.dart';
import 'package:tidy_log/src/core.dart';

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

  test('quiet preset hides start-up chatter but keeps performance and engine lines', () {
    final quiet = NoiseFilter(TidyConfig());
    // Captured from sample_app on an API 37 emulator.
    for (final line in [
      'I/FlutterActivityAndFragmentDelegate(1): If you are attempting to set --enable-dart-profiling via Intent extras',
      'D/FlutterJNI(1): Beginning load of flutter...',
      'D/FlutterJNI(1): flutter (null) was loaded normally!',
      'D/FlutterRenderer(1): Width is zero. 0,0',
      'D/ProfileInstaller(1): Installing profile for dev.tidylog.tidy_log_sample',
      'D/DesktopExperienceFlags(1): Toggle override initialized to: false',
      'I/tidy_log_sample(1): Background concurrent mark compact GC freed 2065KB AllocSpace bytes, 49% free',
    ]) {
      expect(shows(quiet, line), isFalse, reason: line);
    }
    expect(shows(quiet, 'I/Choreographer(1): Skipped 84 frames!  The application may be doing too much work on its main thread.'), isTrue);
    expect(shows(quiet, 'I/flutter(1): [IMPORTANT:flutter/shell/platform/android/android_context_gl_impeller.cc(104)] Using the Impeller rendering backend (OpenGLES).'), isTrue);
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
