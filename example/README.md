# tidy_log: before and after

This app is a small demo with five buttons:
- log one line per level;
- log a caught error;
- throw in a tap handler;
- throw an uncaught async error;
- call an API that refuses the connection.

Below is the same session on an Android emulator, with the same taps (the tap-handler error twice), run both ways. The `flutter run` banner (build lines and key commands) is left out of both.

## After: `dart run tidy_log run` (22 lines)

Shown without colours. In the console, errors are red, warnings yellow, and tags and hidden-frame lines dim.

```text
──────── app started · pid 9739 ────────
INF Using the Impeller rendering backend (OpenGLES).                    · engine
DBG Sending viewport metrics to the engine.                             · FlutterJNI
DBG Sending viewport metrics to the engine.                             · FlutterJNI  ×2
DBG Loaded 12 accounts                                                  · AccountsRepo
INF Signed in {userId: 7, pin: ••••••••}                                · Auth
WRN Token expires in 30 s                                               · Auth
ERR Could not parse the amount                                          · Transfer
    FormatException: Invalid radix-10 number (at character 1)
    at lib/main.dart:76:40  _DemoPageState._parseAmount
    ┊ lib/main.dart:69:7  _DemoPageState._logCaught
    ┊ … 20 frames hidden
ERR Bad state: No account selected                                      · caught by gesture
    while handling a gesture
    at lib/main.dart:80:5  _DemoPageState._throwInHandler
    ┊ … 16 frames hidden
ERR Bad state: No account selected                                      · thrown again
ERR TimeoutException: Session refresh took too long                     · uncaught
    at lib/main.dart:85:57  _DemoPageState._throwAsync.<fn>
    ┊ … 5 frames hidden
POST /api/Auth/Signin  127.0.0.1:9  ERR connection refused  26 ms · 08:39:22
    body  {userId: 7, pin: ••••••••}
```

## Before: `flutter run` (104 lines)

The app logs the way many apps do: `debugPrint`, Dio's `LogInterceptor`, and Flutter's default error box.

```text
I/FlutterActivityAndFragmentDelegate( 9519): If you are attempting to set --enable-dart-profiling via Intent extras to launch a Flutter component outside of using the Flutter CLI, note that support for setting engine flags on Android via Intent will soon be dropped; see https://github.com/flutter/flutter/issues/180686 for more information on this breaking change. To migrate, set --enable-dart-profiling or any other flags specified via Intent extras on the command line instead or see https://github.com/flutter/flutter/blob/main/docs/engine/Flutter-Android-Engine-Flags.md for alternative methods.
D/FlutterJNI( 9519): Beginning load of flutter...
D/FlutterJNI( 9519): flutter (null) was loaded normally!
I/flutter ( 9519): [IMPORTANT:flutter/shell/platform/android/android_context_gl_impeller.cc(104)] Using the Impeller rendering backend (OpenGLES).
D/FlutterRenderer( 9519): Width is zero. 0,0
D/FlutterRenderer( 9519): Width is zero. 0,0
D/FlutterJNI( 9519): Sending viewport metrics to the engine.
D/FlutterJNI( 9519): Sending viewport metrics to the engine.
D/WindowLayoutComponentImpl( 9519): Register WindowLayoutInfoListener on Context=dev.tidylog.tidy_log_example.MainActivity@4025e63, of which baseContext=android.app.ContextImpl@c948fd5
D/FlutterJNI( 9519): Sending viewport metrics to the engine.
D/InsetsController( 9519): hide(ime())
I/ImeTracker( 9519): dev.tidylog.tidy_log_example:dfd480de: onCancelled at PHASE_CLIENT_ALREADY_HIDDEN
D/ProfileInstaller( 9519): Installing profile for dev.tidylog.tidy_log_example
I/flutter ( 9519): [AccountsRepo] Loaded 12 accounts
I/flutter ( 9519): [Auth] Signed in {userId: 7, pin: 1234}
I/flutter ( 9519): [Auth] Token expires in 30 s
I/flutter ( 9519): [Transfer] Could not parse the amount
I/flutter ( 9519): FormatException: Invalid radix-10 number (at character 1)
I/flutter ( 9519): 12,5
I/flutter ( 9519): ^
I/flutter ( 9519): 
I/flutter ( 9519): #0      int._handleFormatError (dart:core-patch/integers_patch.dart:150:5)
I/flutter ( 9519): #1      int._parseRadix (dart:core-patch/integers_patch.dart:179:14)
I/flutter ( 9519): #2      int._parse (dart:core-patch/integers_patch.dart:121:12)
I/flutter ( 9519): #3      int.parse (dart:core-patch/integers_patch.dart:81:12)
I/flutter ( 9519): #4      _DemoPageState._parseAmount (package:tidy_log_example/main.dart:76:40)
I/flutter ( 9519): #5      _DemoPageState._logCaught (package:tidy_log_example/main.dart:69:7)
I/flutter ( 9519): #6      _InkResponseState.handleTap (package:flutter/src/material/ink_well.dart:1224:21)
I/flutter ( 9519): #7      GestureRecognizer.invokeCallback (package:flutter/src/gestures/recognizer.dart:362:24)
I/flutter ( 9519): #8      TapGestureRecognizer.handleTapUp (package:flutter/src/gestures/tap.dart:758:11)
I/flutter ( 9519): #9      BaseTapGestureRecognizer._checkUp (package:flutter/src/gestures/tap.dart:383:5)
I/flutter ( 9519): #10     BaseTapGestureRecognizer.acceptGesture (package:flutter/src/gestures/tap.dart:353:7)
I/flutter ( 9519): #11     GestureArenaManager.sweep (package:flutter/src/gestures/arena.dart:173:27)
I/flutter ( 9519): #12     GestureBinding.handleEvent (package:flutter/src/gestures/binding.dart:542:20)
I/flutter ( 9519): #13     GestureBinding.dispatchEvent (package:flutter/src/gestures/binding.dart:508:22)
I/flutter ( 9519): #14     RendererBinding.dispatchEvent (package:flutter/src/rendering/binding.dart:473:11)
I/flutter ( 9519): #15     GestureBinding._handlePointerEventImmediately (package:flutter/src/gestures/binding.dart:447:7)
I/flutter ( 9519): #16     GestureBinding.handlePointerEvent (package:flutter/src/gestures/binding.dart:404:5)
I/flutter ( 9519): #17     GestureBinding._flushPointerEventQueue (package:flutter/src/gestures/binding.dart:351:7)
I/flutter ( 9519): #18     GestureBinding._handlePointerDataPacket (package:flutter/src/gestures/binding.dart:310:9)
I/flutter ( 9519): #19     _invoke1 (dart:ui/hooks.dart:457:13)
I/flutter ( 9519): #20     PlatformDispatcher._dispatchPointerDataPacket (dart:ui/platform_dispatcher.dart:473:7)
I/flutter ( 9519): #21     _dispatchPointerDataPacket (dart:ui/hooks.dart:374:31)
I/flutter ( 9519): 

══╡ EXCEPTION CAUGHT BY GESTURE ╞═══════════════════════════════════════════════════════════════════
The following StateError was thrown while handling a gesture:
Bad state: No account selected

When the exception was thrown, this was the stack:
#0      _DemoPageState._throwInHandler (package:tidy_log_example/main.dart:80:5)
#1      _InkResponseState.handleTap (package:flutter/src/material/ink_well.dart:1224:21)
#2      GestureRecognizer.invokeCallback (package:flutter/src/gestures/recognizer.dart:362:24)
#3      TapGestureRecognizer.handleTapUp (package:flutter/src/gestures/tap.dart:758:11)
#4      BaseTapGestureRecognizer._checkUp (package:flutter/src/gestures/tap.dart:383:5)
#5      BaseTapGestureRecognizer.acceptGesture (package:flutter/src/gestures/tap.dart:353:7)
#6      GestureArenaManager.sweep (package:flutter/src/gestures/arena.dart:173:27)
#7      GestureBinding.handleEvent (package:flutter/src/gestures/binding.dart:542:20)
#8      GestureBinding.dispatchEvent (package:flutter/src/gestures/binding.dart:508:22)
#9      RendererBinding.dispatchEvent (package:flutter/src/rendering/binding.dart:473:11)
#10     GestureBinding._handlePointerEventImmediately (package:flutter/src/gestures/binding.dart:447:7)
#11     GestureBinding.handlePointerEvent (package:flutter/src/gestures/binding.dart:404:5)
#12     GestureBinding._flushPointerEventQueue (package:flutter/src/gestures/binding.dart:351:7)
#13     GestureBinding._handlePointerDataPacket (package:flutter/src/gestures/binding.dart:310:9)
#14     _invoke1 (dart:ui/hooks.dart:457:13)
#15     PlatformDispatcher._dispatchPointerDataPacket (dart:ui/platform_dispatcher.dart:473:7)
#16     _dispatchPointerDataPacket (dart:ui/hooks.dart:374:31)

Handler: "onTap"
Recognizer:
  TapGestureRecognizer#68653
════════════════════════════════════════════════════════════════════════════════════════════════════

Another exception was thrown: Bad state: No account selected
E/flutter ( 9519): [ERROR:flutter/runtime/dart_vm_initializer.cc(40)] Unhandled Exception: TimeoutException: Session refresh took too long
E/flutter ( 9519): #0      _DemoPageState._throwAsync.<anonymous closure> (package:tidy_log_example/main.dart:85:57)
E/flutter ( 9519): #1      new Future.delayed.<anonymous closure> (dart:async/future.dart:448:42)
E/flutter ( 9519): #2      Timer._createTimer.<anonymous closure> (dart:async-patch/timer_patch.dart:18:15)
E/flutter ( 9519): #3      _Timer._runTimers (dart:isolate-patch/timer_impl.dart:423:19)
E/flutter ( 9519): #4      _Timer._handleMessage (dart:isolate-patch/timer_impl.dart:454:5)
E/flutter ( 9519): #5      _RawReceivePort._handleMessage (dart:isolate-patch/isolate_patch.dart:192:12)
E/flutter ( 9519): 
I/flutter ( 9519): *** Request ***
I/flutter ( 9519): uri: http://127.0.0.1:9/api/Auth/Signin
I/flutter ( 9519): method: POST
I/flutter ( 9519): responseType: ResponseType.json
I/flutter ( 9519): followRedirects: true
I/flutter ( 9519): persistentConnection: true
I/flutter ( 9519): connectTimeout: 0:00:02.000000
I/flutter ( 9519): sendTimeout: null
I/flutter ( 9519): receiveTimeout: null
I/flutter ( 9519): transformTimeout: null
I/flutter ( 9519): receiveDataWhenStatusError: true
I/flutter ( 9519): extra: {}
I/flutter ( 9519): headers:
I/flutter ( 9519):  content-type: application/json
I/flutter ( 9519): data:
I/flutter ( 9519): {userId: 7, pin: 1234}
I/flutter ( 9519): 
I/flutter ( 9519): *** DioException ***:
I/flutter ( 9519): uri: http://127.0.0.1:9/api/Auth/Signin
I/flutter ( 9519): DioException [connection error]: The connection errored: Connection refused This indicates an error which most likely cannot be solved by the library.
I/flutter ( 9519): Error: SocketException: Connection refused (OS Error: Connection refused, errno = 111), address = 127.0.0.1, port = 35964
I/flutter ( 9519): 
```

## Run it yourself

```bash
cd example
flutter run -d <device> --dart-define=TIDY=false   # before
dart run tidy_log run -d <device>                  # after
```

In VS Code, the "example (tidy logs)" launch config does the same as the second command. It was set up with `dart run tidy_log:setup`.

The app code is in [lib/main.dart](lib/main.dart). It's the usual setup:

```dart
void main() {
  TidyLog.configure(projectPackages: ['tidy_log_example']);
  TidyLog.installErrorHooks(); // before Sentry or any other crash reporter
  runApp(const ExampleApp());
}

final dio = Dio()..interceptors.add(TidyDioInterceptor());
TidyLog.e('Could not parse the amount', tag: 'Transfer', error: error, stackTrace: stack);
```
