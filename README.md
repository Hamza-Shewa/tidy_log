# tidy_log

Readable Flutter debug logs in the VS Code Debug Console (F5), for Android.

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

## How it works

There are two independent parts. You can use either one alone.

| Part | What it does | Where |
|---|---|---|
| `tidy_flutter` wrapper | Dart-Code's `customTool`. It runs the real `flutter`, passes the debug adapter's JSON through untouched, and restyles the device log lines. Breakpoints, hot reload and DevTools keep working. | `packages/tidy_log_core` |
| `tidy_log` package | `TidyLog.d/i/w/e`, Flutter error hooks and a Dio interceptor in your app. Its lines are pre-styled, and the wrapper passes them through as they are. | `packages/tidy_log` |

The native `X/Tag(pid):` lines come from the Flutter tool, which forwards logcat. App code can't change them, which is why the wrapper exists.

## Setup

### In short

```bash
tool/install.sh   # builds build/tidy_flutter: the program VS Code runs instead of `flutter`
```

On Windows, from `packages/tidy_log_core`: `dart compile exe bin/tidy_flutter.dart -o ../../build/tidy_flutter.exe`.

```jsonc
// your app's .vscode/launch.json
{
  "name": "app (tidy logs)",        // the name in VS Code's Run menu
  "type": "dart",                   // a Dart/Flutter launch (Dart-Code extension)
  "request": "launch",              // start the app, don't attach to a running one
  "program": "lib/main.dart",       // your app's entry point
  "customTool": "<path to tidy_log>/build/tidy_flutter", // run the wrapper instead of flutter (.exe on Windows)
  "customToolReplacesArgs": 0       // keep every flutter argument; the wrapper passes them all on
}
```

```yaml
# your app's pubspec.yaml
dependencies:
  tidy_log:
    path: <path to tidy_log>/packages/tidy_log   # the in-app logger (optional; the wrapper works without it)
```

```dart
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

final dio = Dio()..interceptors.add(TidyDioInterceptor()); // one line per HTTP call, instead of a pretty logger
```

Optional: a `tidy_log.yaml` next to `pubspec.yaml` tunes the wrapper (which native tags to hide, and more; see Configuration).

The steps below explain each part in more detail.

### 1. Build the wrapper (once, and again after updating tidy_log)

```bash
~/workspace/tinkering/tidy_log/tool/install.sh
```

This compiles `build/tidy_flutter`, a native binary, so F5 doesn't wait for Dart to compile it on each launch.

### 2. Point your app's launch config at it

In the app's `.vscode/launch.json`:

```json
{
  "name": "app (tidy logs)",
  "type": "dart",
  "request": "launch",
  "program": "lib/main.dart",
  "customTool": "/Users/<you>/workspace/tinkering/tidy_log/build/tidy_flutter",
  "customToolReplacesArgs": 0
}
```

Keep your existing config next to it, so you can switch back to plain output from the Run menu.

The wrapper finds the real `flutter` from `TIDY_FLUTTER_BIN`, then `FLUTTER_ROOT`, then `PATH`.

### 3. (Optional) Use the package in the app

```yaml
dev_dependencies: # or dependencies
  tidy_log:
    path: ../tinkering/tidy_log/packages/tidy_log
```

```dart
void main() {
  TidyLog.configure(projectPackages: ['app', 'core_kit']); // first = the app itself
  TidyLog.installErrorHooks(); // before Sentry or any other crash reporter
  runApp(const App());
}

TidyLog.i('Signed in', tag: 'Auth');
TidyLog.e('Transfer failed', tag: 'Transfer', error: e, stackTrace: s);
dio.interceptors.add(TidyDioInterceptor()); // instead of a Dio pretty logger
```

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
tidy_flutter run -d emulator-5554                        # flutter run in a terminal, tidied
adb logcat | tidy_flutter rewrite                        # any logcat stream
tidy_flutter rewrite --plain < saved.log > clean.log     # clean a saved log
```

## If the wrapper is not an option

The package still works without it. To hide native noise with the built-in Debug Console filter, type this into its filter box:
`!FlutterJNI, !WindowOnBackDispatcher, !InsetsController, !ImeTracker`

## Limits

- Android only for the native part. iOS has no logcat prefixes, but the package still works there.
- Repeat counts and open blocks are held back until the next different line, or until the output has been quiet for 200 ms.
- Dart-Code links paths in the console. `lib/…` paths open from the workspace root, and `package:` paths are resolved by the debug adapter.

## Development

```bash
cd packages/tidy_log_core && dart test          # core: parser, folding, collapsing, redaction, golden session
cd packages/tidy_log && flutter test            # logger, error hooks, Dio interceptor
cd example && flutter test                      # demo screen
```

`packages/tidy_log_core/test/fixtures/sample_session.txt` is a real F5 session excerpt, with PINs and user IDs replaced. Its expected output is reviewed by hand. See `test/golden_session_test.dart` for how to regenerate it after an intended change.
