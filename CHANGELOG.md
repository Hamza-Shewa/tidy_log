## 0.2.2

### Changed

- `dart run tidy_log:setup` puts the `(tidy logs)` launch configs first in `.vscode/launch.json`, so VS Code picks a tidy launch by default. Running it again in a project set up by 0.2.1 or earlier moves the existing tidy configs to the top, text unchanged. `--remove` still restores the file exactly.

### Fixed

- Build, layout and paint errors (a missing `Material`, a `RenderFlex` overflow) now point at the nearest widget created in your code. The location used to come from the stack, which has no frame of yours for these errors, so it showed a framework file. tidy_log now walks up from the failing element instead, skipping the pub cache and the Flutter SDK, on every supported Flutter version.

## 0.2.1

0.2.0 could print some secrets unmasked: values with spaces, commas or `&` in them, URL-encoded query values, values nested in bodies, coloured lines from other loggers, and the repeated `thrown again` error line. Upgrading is recommended.

### Fixed

#### Secret masking

- Values are masked whole: a quoted value up to its closing quote, an unquoted one to the end of the field, a list as a whole. A value with `,`, `&`, `|`, `}`, a quote or a space in it was cut short and its tail printed.
- URL query values are masked before percent-decoding. `?password=Tom%26Jerry1` used to print `&Jerry1`.
- In-app bodies: everything nested under a sensitive key is masked (`token: {access: …, refresh: …}`).
- Keys inside escaped JSON (`\"password\"`) and bracketed form keys (`user[password]`) are found.
- `Authorization` values are masked whole for `Bearer`, `Basic`, `Token` and `Digest`.
- Coloured lines from other loggers are masked. Only TidyLog's own lines, already masked in the app, pass through as they are.
- A pretty_dio_logger box that arrives in pieces (a line from another tag inside it, a pause, or more than 400 lines) no longer spills raw box lines, which could show the end of a wrapped token. Extra lines are counted instead.
- The short `thrown again` line for a repeated Flutter error is masked.
- New default keys: `pincode`, `otpcode`, `cvv2`, `cvc`, `apikey`, `cookie`, `setcookie`, `sessionid`, `privatekey`, `accesskey`. Keys still match by their ending, so `pinCount` and `tokenExpiry` are left alone.

#### Logging never changes app behaviour

- Every logging path is guarded. A `printer`, `toString()`, `errorText` hook or response rule that throws can no longer fail a Dio call or escape `TidyLog`.
- Request timing no longer uses `RequestOptions.extra`. A request built with an unmodifiable `extra` no longer fails, and other interceptors no longer see the start time.
- `installErrorHooks()` does nothing when logging is disabled: in profile and release builds, and after `configure(enabled: false)`. It used to swallow Flutter errors and uncaught async errors there without printing them.
- Calling `installErrorHooks()` twice is safe.
- A response rule that throws is reported once per rule. It was reported on every call.
- A URL with a non-UTF-8 escape (`?name=Jos%E9`) no longer throws while it is logged.

#### Runner and setup

- Only `flutter run` and `flutter attach` are restyled. Other commands (`test`, `build`, `doctor`, …) pass through untouched.
- `setup` no longer adds "(tidy logs)" copies of test launch configs.
- Partial lines, such as build progress and prompts, show at once instead of after their newline.
- The Flutter tool's stderr is masked and saved to `.dart_tool/tidy_log/last_run.log`.
- A mistake in `tidy_log.yaml` prints one line naming it and exits with code 64, instead of a stack trace. A `rules` entry with no `match` or an unknown `tone` is now reported this way; it used to be skipped silently.
- A line the restyler cannot handle is printed as it is (masked), and the run goes on. A broken pipe on the Flutter tool's input no longer replaces its exit code.
- A pretty_dio_logger box that is still arriving is printed about 2 s after the output goes quiet, instead of waiting for the next line.
- `rewrite --plain` keeps `http_rules`.
- `setup --remove` keeps "(tidy logs)" configs you edited, with a note, as it already did for edited launchers. Duplicate config names get distinct copies. An existing `windows.customTool` is kept, with a note.
- `setup` marks `.vscode/tidy_flutter` executable in git when it is already tracked, and suggests `*.bat text eol=crlf` in `.gitattributes` when that rule is missing. It never edits `.gitattributes`.

#### Windows

- `setup --remove` removes everything setup added to `.vscode`.
- `setup --sdk` creates directory junctions, so it no longer needs Developer Mode or an administrator shell.
- The `.bat` launchers handle `%` in paths. Rerunning `setup` updates a 0.2.0 launcher instead of reporting that it differs from the template.
- The tests run in CI on Linux, macOS and Windows.

## 0.2.0

HTTP entries have a new layout. Each call is a head line in fixed columns, with the reason, body and response on the lines below, one field per line. Anything that reads the 0.1.0 one-line form needs updating. The public API is unchanged.

### Added

- The runner folds pretty_dio_logger-style boxes (`╔╣ Request ║ GET`, `╔╣ Response`, `╔╣ DioError`) from any package into the same HTTP entry. Each request is paired with its response by URL. Headers, query tables and timeouts are dropped. A request with no answer by the end of the run is listed as `no response logged`.
- `http_rules` in `tidy_log.yaml` judge those folded calls by their body, as `ResponseRule.field` does in the app. A mistyped outcome stops the run with a message naming the rule.
- In a terminal, lines are fitted to the window width. Elsewhere `max_width` (default 160) applies. The `· Tag` suffix stays visible.

### Changed

- HTTP head line: method (7 columns), path (46), status and rule mark (`✕` / `!`), duration, time, host. Sources without timing skip the empty columns. The failure reason and transport errors go on their own line. The `rule` line shows only for warnings and errors.
- Bodies are shown one field per line (maps, nested maps, lists as `- item`, JSON text decoded), up to 14 lines of 110 characters. Empty bodies are left out.
- Status colours: 3xx and info are light yellow (were cyan). A 5xx that ends as an error is magenta, so a server failure looks different from an error the API reports in a 200 body (red). 4xx stays yellow.
- File locations get their own colour: bright blue in the `at …` line, blue in the trail.
- Paths and queries are shown percent-decoded (`<redacted>`, not `%3Credacted%3E`).
- Blank Dart lines are no longer shown.

### Fixed

- A key is sensitive when it ends with a secret word (`softToken`, `refreshToken`, `walletPin`, `newPassword`). A key that is not sensitive no longer hides the next one (`state: token: abc`).
- JWTs are masked wherever they appear, with or without a key. Bodies are masked before they are shortened.
- `TidyDioInterceptor` masks the URL too.

## 0.1.0

First release.

- `dart run tidy_log run …`: runs `flutter run` (or `attach`) and restyles the device log. Native logcat prefixes become a dim tag suffix, repeats collapse to `×N`, Java and printed Dart traces lead with the first useful frame, Dio boxes become one line with secrets masked, and process and hot reload get dividers. A plain clean copy goes to `.dart_tool/tidy_log/last_run.log`.
- `dart run tidy_log:setup`: sets up VS Code (launcher scripts and "(tidy logs)" launch configs). `--remove` undoes it.
- `dart run tidy_log:setup --sdk`: a shim Flutter SDK (symlinks to your real SDK, which is never modified) for Android Studio and IntelliJ.
- In-app logger: `TidyLog.d/i/w/e`, `installErrorHooks()` for location-first Flutter and async errors, and `TidyDioInterceptor` with response rules for "200, but it failed" bodies.
- `tidy_log.yaml` for presets, hidden and shown tags, levels, redaction keys and label rules.
