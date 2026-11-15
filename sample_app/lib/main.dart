import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:tidy_log/tidy_log.dart';

import 'api/mock_server.dart';
import 'demos/api_demo.dart';
import 'demos/dart_error_demo.dart';
import 'demos/log_demo.dart';
import 'demos/platform_demo.dart';
import 'logging/app_logger.dart';
import 'pages/home_page.dart';
import 'platform/native_bridge.dart';
import 'scenarios/catalog.dart';
import 'scenarios/scenario.dart';

/// `--dart-define=TIDY=false` runs with Flutter's default error output and
/// Dio's own LogInterceptor, for comparison.
const _tidy = bool.fromEnvironment('TIDY', defaultValue: true);

/// `--dart-define=AUTORUN=true` taps every scenario once after start-up.
const _autorun = bool.fromEnvironment('AUTORUN');

Future<void> main() async {
  if (_tidy) {
    TidyLog.configure(projectPackages: ['tidy_log_sample']);
    // Before any crash reporter, so it calls the tidy formatter.
    TidyLog.installErrorHooks();
  }
  WidgetsFlutterBinding.ensureInitialized();

  final server = await MockServer.start();
  final AppLogger logger = _tidy ? const TidyAppLogger() : const PlainAppLogger();
  final dio = Dio(
    BaseOptions(
      baseUrl: server.baseUri.toString(),
      connectTimeout: const Duration(seconds: 2),
      receiveTimeout: const Duration(seconds: 1),
    ),
  )..interceptors.add(_tidy ? TidyDioInterceptor() : LogInterceptor(requestBody: true, responseBody: true, logPrint: (o) => debugPrint('$o')));

  final demos = Demos(
    logs: LogDemo(logger),
    dart: DartErrorDemo(logger),
    api: ApiDemo(dio, logger),
    platform: PlatformDemo(const NativeBridge(), DefaultBiometrics(), logger),
  );

  runApp(SampleApp(demos: demos, tidy: _tidy, autorun: _autorun));
}

class SampleApp extends StatelessWidget {
  const SampleApp({super.key, required this.demos, required this.tidy, this.autorun = false});

  final Demos demos;
  final bool tidy;
  final bool autorun;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'tidy_log sample',
      theme: ThemeData(colorSchemeSeed: Colors.indigo),
      darkTheme: ThemeData(colorSchemeSeed: Colors.indigo, brightness: Brightness.dark),
      home: HomePage(
        scenarios: scenarios,
        demos: demos,
        modeLabel: tidy ? 'tidy_log: on' : 'tidy_log: off (default Flutter output)',
        autorun: autorun,
      ),
    );
  }
}
