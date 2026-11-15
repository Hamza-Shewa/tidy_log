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

export 'package:tidy_log_core/tidy_log_core.dart' show HttpOutcome, Level;

export 'src/dio_interceptor.dart' show TidyDioInterceptor;
export 'src/error_text.dart' show ErrorText;
export 'src/http_rules.dart' show HttpBodies, ResponseRule, RuleVerdict;
export 'src/tidy_log.dart' show TidyLog;
