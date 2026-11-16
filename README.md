# tidy_log

Readable Flutter debug logs for Android, in VS Code, Android Studio, IntelliJ or a terminal.

- Errors open with **where** they happened (`at lib/app/view/home_page.dart:145:12  HomePage._onTap`), followed by a short dimmed trail of your own frames and a count of hidden frames.
- Native logcat lines lose their `D/WindowOnBackDispatcher(31800):` prefix. The tag moves to a dim suffix, and the level becomes a coloured `DBG / INF / WRN / ERR` label.
- Noise is handled for you:
  - Identical lines collapse into one line with `×30`.
  - Near-duplicates fold into `↳ +6 similar`.
  - Native Java stack traces fold to the exception, the first non-SDK frame and the `caused by` line.
  - Chatty Android tags are hidden by default.
- Dio calls become one line each (`POST /api/Auth/Signin  401  1,003 ms`), coloured by status, with PINs, passwords and tokens masked. Response rules can flag a 200 whose body says it failed (`200 ✕ Insufficient balance`).
- Each new app process gets a divider, and so does each hot restart.
- Every run also writes a **clean copy** to `.dart_tool/tidy_log/last_run.log`, in plain text with no colours and no tags, ready to paste.

```
──────── app started · pid 31800 ────────
ERR EncryptedSharedPreferences initialization failed. Falling back…     · FlutterSecureStorage
    SecurityException: Could not decrypt key. decryption failed
    at com.it_nomads.fluttersecurestorage.crypto.EncryptedSharedPreferences.decryptKey(…:561)
    ┊ … 6 frames hidden · caused by GeneralSecurityException: decryption failed
DBG Sending viewport metrics to the engine.                             · FlutterJNI  ×30
NAV /login → /loginSelectAccountPage
POST /api/Auth/OpenSession  10.0.2.2:4013  200  1,010 ms · 15:22:58
    resp  {"type":2,"messages":["unvalid api sign .....en-US"],…}
ERR Error refreshing session: unvalid api sign .....en-US
    at package:core_kit/infrastructure/network/httpHandler/handle_exception.dart:42:5  HandleException.handleException
    ┊ package:core_kit/…/network_service_impl.dart:97:14  NetworkServiceImpl.requestService
```

**Before and after:** the same demo session is 104 lines with `flutter run` and 22 with tidy_log. Both logs are in full on [the example page](example/README.md) (the **Example** tab on pub.dev).

## Setup

```bash
flutter pub add dev:tidy_log
```

Then, depending on where you run your app:

| You run the app from | Do this once | Then |
|---|---|---|
| A terminal | nothing | `dart run tidy_log run -d <device>` instead of `flutter run -d <device>` (every `flutter run` flag works) |
| VS Code | `dart run tidy_log:setup` | pick a "(tidy logs)" config in Run and Debug and press F5 |
| Android Studio / IntelliJ | `dart run tidy_log:setup --sdk` (once per machine) | set Settings → Languages & Frameworks → Flutter → SDK path to the folder it prints |

That's all the native part needs. The in-app logger below is optional.

### What `dart run tidy_log:setup` does (VS Code)

- It writes `.vscode/tidy_flutter` and `.vscode/tidy_flutter.bat`. These are small launchers that start `dart run tidy_log` with your project's Flutter SDK. Until `flutter pub get` has run, they fall back to plain flutter, so a fresh clone always launches.
- It adds a `<name> (tidy logs)` copy of every Dart config in `.vscode/launch.json`, or creates the file. Your own configs, comments and formatting are left exactly as they are.
- It prints an optional `main.dart` snippet that uses your app's package name.

Commit the three files so your team gets them. `--dry-run` shows the changes first, and `--remove` undoes them.

### What `dart run tidy_log:setup --sdk` does (Android Studio / IntelliJ)

The JetBrains Flutter plugin runs `<Flutter SDK path>/bin/flutter run --machine` itself, and has no option to run another program. So setup creates a **shim SDK** at `~/.tidy_log/flutter_sdk`:
- **It's a few KB of symlinks.** They point to your real SDK, which is never copied or modified, so `flutter upgrade` keeps working.
- **Only `bin/flutter` is different.** It's a small script:
  - `flutter run` and `flutter attach`, in projects that depend on tidy_log, go through tidy_log.
  - Every other command, and every other project, goes straight to your real Flutter.

To keep typing plain `flutter run` in a terminal too, put the shim's `bin` first in your `PATH` (setup prints the line). Rerun `--sdk` after moving your SDK. `--sdk --remove` deletes the shim, and you can always point the IDE back at your real SDK.

### How it works

The native `X/Tag(pid):` lines come from the Flutter tool, which forwards logcat. App code can't change them, so tidy_log sits between your IDE and `flutter`:
- It runs the real `flutter` and passes the IDE's JSON protocol through untouched, so breakpoints, hot reload and DevTools keep working.
- It restyles only the device log lines.

The runner finds the real `flutter` from `TIDY_FLUTTER_BIN`, then `FLUTTER_ROOT`, then `PATH`.

## In-app logger (optional)

To call `TidyLog` from your code, add tidy_log as a regular dependency (`flutter pub add tidy_log`) rather than a dev one.

```dart
import 'package:tidy_log/tidy_log.dart';

void main() {
  TidyLog.configure(
    projectPackages: ['app', 'core_kit'], // your own packages; the first is the app, so its paths print as lib/…
    minLevel: Level.debug,                // the lowest level that is printed
    httpBodies: HttpBodies.always,        // body/resp lines: always (default), onFailure or never
    httpRules: [/* … */],                 // how to read "200, but it failed" bodies (see Response rules)
    redactKeys: ['pin', 'password', 'token'], // keys whose values are masked (these and a few more by default)
  );
  TidyLog.installErrorHooks();            // tidy Flutter errors and uncaught async errors; call it before Sentry
  runApp(const App());
}

TidyLog.i('Signed in', tag: 'Auth');
TidyLog.e('Transfer failed', tag: 'Transfer', error: e, stackTrace: s);
final dio = Dio()..interceptors.add(TidyDioInterceptor()); // one line per HTTP call, instead of a pretty logger
```

`dart run tidy_log:setup` prints this snippet with your app's package name filled in.

`installErrorHooks()` replaces Flutter's `══╡ EXCEPTION CAUGHT ╞══` box, and logs uncaught async errors. Every error gets its own location line, including the ones Flutter would print only as `Another exception was thrown: …`. Errors that are just side effects of the one before (the dozen `RenderBox was not laid out` after an unbounded-height error) are folded into one `┊ +12 follow-on errors hidden` line.

**Order matters:** call it before Sentry's init. Crash reporters keep the `FlutterError.onError` handler they find and call it after capturing an error. If the reporter is set up first, it keeps Flutter's box printer instead. The hooks then leave the reporter alone and print a one-line hint.

The hooks print errors themselves rather than through `FlutterError.presentError`, because in debug runs the widget inspector replaces `presentError` once the binding starts. To keep the IDE's structured errors instead, use `installErrorHooks(keepStructuredErrors: true)`.

Some errors get a short description instead of their `toString()`:

| Error | Printed as |
|---|---|
| `DioException` | `DioException · receive timeout (1 s)`, `· bad response 500`, `· connection refused`, `· host lookup failed: api.x` |
| `PlatformException` | `PlatformException(UNAVAILABLE): Card reader is not connected.`, then `native at <first app frame>` and a `caused by` note when it carries a Java stack |
| `FlutterError` (uncaught) | the summary and the first two hint lines |

Add your own with `TidyLog.configure(errorText: (e) => e is ApiFailure ? 'ApiFailure ${e.code}' : null)`.

### HTTP calls

The status is green for 2xx, cyan for 3xx, yellow for 4xx and red for 5xx. A call that never got a response shows `ERR` and a short reason. Each call is logged at the level of its outcome, so `TidyLog.configure(minLevel: Level.warning)` hides the successful ones.

`body` and `resp` lines are printed for every call by default. Choose for yourself:

```dart
TidyLog.configure(httpBodies: HttpBodies.onFailure); // or always (default), never
dio.interceptors.add(TidyDioInterceptor(bodies: HttpBodies.never)); // per client, wins over configure
```

### Response rules: "200, but it failed"

Some backends answer 200 to everything and put the real result in the body. Tell tidy_log how to read it, and the line is coloured by what really happened:

```dart
TidyLog.configure(httpRules: [ // or TidyDioInterceptor(rules: [...]) for one client
  // {"success": false, "message": "Insufficient balance"}
  ResponseRule.field('success', {true: HttpOutcome.success, false: HttpOutcome.error}, message: 'message'),
  // {"response_type": "WARNING", "messages": ["Session expires in 2 minutes"]}
  ResponseRule.field('response_type', {
    'SUCCESS': HttpOutcome.success,
    'WARNING': HttpOutcome.warning,
    'ERROR': HttpOutcome.error,
  }, message: 'messages'),
  // {"type": 2, ...} only on the auth service
  ResponseRule.field('type', {2: HttpOutcome.error}, message: 'messages',
      when: (request) => request.path.startsWith('/api/Auth')),
  // anything else
  ResponseRule.custom((response) => (response.data as Map?)?['errors'] != null
      ? const RuleVerdict(HttpOutcome.error, message: 'has errors')
      : null),
]);
```

```
POST /api/wallet/pay        127.0.0.1:45887  200 ✕ Insufficient balance  12 ms · 21:48:42
    rule  success = false → error
GET  /api/session           127.0.0.1:45887  200 ! Session expires in 2 minutes  4 ms · 21:48:42
POST /api/Auth/OpenSession  10.0.2.2:4013    200 ✕ unvalid api sign  1,010 ms · 15:22:58
    rule  type = 2 → error
```

- The path is dotted (`meta.errors.0.code`). Bodies that arrive as JSON text are decoded.
- Values match leniently: `2` matches `'2'`, and strings match whatever their case.
- `message:` points at a string, or at a list whose first item is used.
- A value missing from the map gets `otherwise:`, or no verdict at all (the status colour stays).
- Rules also run on error responses, so a 400 can be just a warning. The first rule with a verdict wins.
- Rules only change the log line (colour, level, message). They never change what Dio does. A rule that throws is reported once as a `WRN`, and the call is still logged.

## Configuration: `tidy_log.yaml` in the app root

Every key is optional.

```yaml
preset: quiet            # quiet (default) hides Android UI chatter; all shows everything restyled
project_packages: [app, core_kit]   # the app's own name from pubspec.yaml is added first automatically
hide_tags: [FlutterGeolocator]
show_tags: [ImeTracker]  # wins over the preset and hide_tags
hide_messages: ['^Width is zero']
min_native_level: debug  # verbose | debug | info | warning | error
redact_keys: [pin, password, passcode, otp, token, secret, cvv, authorization]
max_width: 220           # long head lines are shortened in the console (never in the clean copy)
color: true              # or set NO_COLOR=1
rules:                   # label your own Dart print lines
  - match: '^unhandled element'
    label: SVG
    tone: warning        # plain dim secondary error warning accent success
```

The `quiet` preset hides these tags: WindowOnBackDispatcher, InsetsController, ImeTracker, InputConnectionAdaptor, Surface, HWUI, nativeloader, `cr_*`, CompatChangeReporter, Badge, NexusLauncherBadge, ApplicationLoaders, ResourcesManager, `VRI[*`, ViewRootImpl, WindowExtensionsImpl, WindowLayoutComponentImpl, UiContextUtils, AudioSystem, libc, DefaultDispatch, InteractionJankMonitor, FlutterActivityAndFragmentDelegate, ProfileInstaller and DesktopExperienceFlags. It also hides `avc: denied/granted` lines and these start-up messages: `Beginning load of flutter`, `flutter (null) was loaded normally!`, `Width is zero` and ART's `… GC freed …`. `Skipped N frames!` stays, because it is a real performance signal.

## Other uses

```bash
dart run tidy_log run -d emulator-5554                       # flutter run in a terminal, tidied
adb logcat | dart run tidy_log rewrite                       # any logcat stream
dart run tidy_log rewrite --plain < saved.log > clean.log    # clean a saved log
```

If you can't use the runner, the package still works on its own. To hide native noise in VS Code, type this into the Debug Console's filter box:
`!FlutterJNI, !WindowOnBackDispatcher, !InsetsController, !ImeTracker`

## Limits

- Android only for the native part. iOS has no logcat prefixes, but the package still works there.
- The Windows launchers (`.bat`) and the shim on Windows are untested.
- Repeat counts and open blocks are held back until the next different line, or until the output has been quiet for 200 ms.
- Dart-Code links paths in the console. `lib/…` paths open from the workspace root, and `package:` paths are resolved by the debug adapter.

## Development

```bash
flutter test                  # the package: parser, folding, redaction, golden session, logger, hooks, setup, shim
cd example && flutter test    # demo screen
```

`test/core/fixtures/sample_session.txt` is a real F5 session excerpt, with PINs and user IDs replaced. Its expected output is reviewed by hand. See `test/core/golden_session_test.dart` for how to regenerate it after an intended change.

`sample_app/` is a scenario bench that compares tidy_log with the default output (see its README).
