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

export 'package:tidy_log_core/tidy_log_core.dart' show Level;

export 'src/dio_interceptor.dart' show TidyDioInterceptor;
export 'src/tidy_log.dart' show TidyLog;
