/// Styled, readable debug console logs for Flutter.
///
/// ```dart
/// void main() {
///   TidyLog.configure(projectPackages: ['app', 'core_kit']);
///   TidyLog.installErrorHooks();
///   runApp(const App());
/// }
/// ```
library;

export 'src/core.dart' show HttpOutcome, Level;

export 'src/flutter/dio_interceptor.dart' show TidyDioInterceptor;
export 'src/flutter/error_text.dart' show ErrorText;
export 'src/flutter/http_rules.dart' show HttpBodies, ResponseRule, RuleVerdict;
export 'src/flutter/tidy_log.dart' show TidyLog;
