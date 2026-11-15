# tidy_log

Readable Flutter debug logs in the VS Code Debug Console (F5), for Android.

- Errors open with **where** they happened (`at lib/app/view/home_page.dart:145:12  HomePage._onTap`), followed by a short dimmed trail of your own frames and a count of hidden frames.
- Native logcat lines lose their `D/WindowOnBackDispatcher(31800):` prefix. The tag moves to a dim suffix, and the level becomes a coloured `DBG / INF / WRN / ERR` label.
- Noise is handled for you:
  - Identical lines collapse into one line with `×30`.
  - Near-duplicates fold into `↳ +6 similar`.
  - Native Java stack traces fold to the exception, the first non-SDK frame and the `caused by` line.
  - Chatty Android tags are hidden by default.
- Dio boxes become one line per call (`POST /api/Auth/Signin  401  1,003 ms`), with PINs, passwords and tokens masked.
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

`installErrorHooks()` replaces Flutter's `══╡ EXCEPTION CAUGHT ╞══` box, and logs uncaught async errors.

**Order matters:** call it before Sentry's init. Crash reporters keep the `FlutterError.onError` handler they find and call it after capturing an error. If the reporter is set up first, it keeps Flutter's box printer instead. The hooks then leave the reporter alone and print a one-line hint.

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

The `quiet` preset hides these tags: WindowOnBackDispatcher, InsetsController, ImeTracker, InputConnectionAdaptor, Surface, HWUI, nativeloader, `cr_*`, CompatChangeReporter, Badge, NexusLauncherBadge, ApplicationLoaders, ResourcesManager, `VRI[*`, ViewRootImpl, WindowExtensionsImpl, WindowLayoutComponentImpl, UiContextUtils, AudioSystem, libc, DefaultDispatch and InteractionJankMonitor. It also hides `avc: denied/granted` lines.

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
