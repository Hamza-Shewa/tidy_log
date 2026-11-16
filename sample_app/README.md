# tidy_log_sample

An Android app that triggers common Flutter failures on purpose, so you can
compare the console with and without tidy_log. The existing `example/` app
shows the package API; this one is a test bench with 43 scenarios.

| Group | Scenarios |
|---|---|
| Log lines | each level (PIN/password in the text), 25 repeats (folded to ×25) and 8 numbered lines, raw `debugPrint` with a token |
| Dart errors | null check, bad cast from JSON, `RangeError`, `.first` on empty list, failed `assert`, caught `FormatException`, uncaught async `TimeoutException`, `LateInitializationError`, stream error with no `onError`, 200-frame recursion, `setState()` after `dispose()`, unknown named route |
| Build and layout | null in `build` (red screen), `Row` overflow, `ListView` in a `Column` (unbounded height), `TextField` in a `Row` (unbounded width), `Expanded` in a `Stack`, the same build error on every frame, `Image.network` that cannot load |
| API calls (Dio) | 200 GET, 200 POST sign-in, 401, 404, 500, receive timeout, malformed JSON, connection refused, unknown host; and "200 for everything" bodies: `success: true`, `success: false`, `response_type: "WARNING"`, `type: 2`, a 400 with `response_type: "ERROR"` |
| Platform channels | battery level (success), native `result.error`, native handler throws (Java stack), `notImplemented`, channel with no plugin (`MissingPluginException`), platform interface throwing `UnimplementedError`, native logcat lines at every level with a Java stack and ×30 repeats |

The API scenarios talk to a small HTTP server the app starts on the device's
loopback interface (`lib/api/mock_server.dart`), so they need no network.
The two "cannot connect" cases use `127.0.0.1:9` and `api.sample.invalid`.
The native side of the channel is `android/app/src/main/kotlin/.../MainActivity.kt`.

In tidy mode, `lib/api/response_rules.dart` tells tidy_log how this backend
reports the real result, so `POST /api/wallet/pay  200 ✕ Insufficient balance`
is red even though the status is 200. See "Response rules" in the root README.

## Modes

| How you start it | What you see |
|---|---|
| `tidy_flutter run` (or the "tidy_log + wrapper" launch config) | tidy_log package **and** the wrapper restyling native logcat lines |
| `flutter run` | tidy_log package only; native lines keep their `D/Tag(pid):` prefix |
| `flutter run --dart-define=TIDY=false` | Flutter's default error boxes, `debugPrint` logging and Dio's `LogInterceptor`; nothing masked |

Add `--dart-define=HTTP_BODIES=onFailure` (or `never`) to print the `body`
and `resp` lines only for failed calls; the default is `always`.

Add `--dart-define=AUTORUN=true` to tap every scenario once after start-up
(a `>>> scenario <id>` marker is printed before each), or press **Run all**
in the app. "Run all" sends real pointer events, so a throwing tap handler
reaches Flutter the same way a finger tap does.

## Capturing a comparison

```bash
cd sample_app
flutter run -d emulator-5554 --dart-define=TIDY=false --dart-define=AUTORUN=true > logs/native_default.log
../build/tidy_flutter run -d emulator-5554 --dart-define=AUTORUN=true > logs/tidy_wrapped.log
```

Press `q` once `>>> run all done` appears. The wrapper also writes a clean
copy to `.dart_tool/tidy_log/last_run.log`. Build the wrapper first with
`tool/install.sh` (on Windows: `dart compile exe bin/tidy_flutter.dart -o ../../build/tidy_flutter.exe`
from `packages/tidy_log_core`). `logs/` is git-ignored.

## Tests

```bash
flutter test
```

The broken pages are checked to raise exactly the error they promise, the API
scenarios run against the real mock server, and the platform scenarios run
against a mock channel that answers like `MainActivity.kt`.
