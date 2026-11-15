import 'dart:async';

import 'package:flutter/widgets.dart';

import '../demos/api_demo.dart';
import '../demos/dart_error_demo.dart';
import '../demos/log_demo.dart';
import '../demos/platform_demo.dart';

/// The demo objects a scenario can use. Built once in `main.dart`.
final class Demos {
  const Demos({required this.logs, required this.dart, required this.api, required this.platform});

  final LogDemo logs;
  final DartErrorDemo dart;
  final ApiDemo api;
  final PlatformDemo platform;
}

/// Runs a scenario. May throw (that is often the point), return a status
/// line for the screen, or return null.
typedef ScenarioAction = FutureOr<String?> Function(BuildContext context, Demos demos);

enum ScenarioGroup {
  logs('Log lines'),
  dart('Dart errors'),
  layout('Build and layout errors'),
  api('API calls'),
  platform('Platform channels');

  const ScenarioGroup(this.label);
  final String label;
}

/// One button on the home screen.
final class Scenario {
  const Scenario({
    required this.id,
    required this.group,
    required this.title,
    required this.expected,
    required this.run,
    this.opensPage = false,
    this.settle = const Duration(milliseconds: 700),
  });

  /// Stable id, printed as a marker during "Run all".
  final String id;
  final ScenarioGroup group;
  final String title;

  /// What should show up in the console, shown under the title.
  final String expected;
  final ScenarioAction run;

  /// Pushes a page; "Run all" pops it again after [settle].
  final bool opensPage;

  /// How long "Run all" waits before the next scenario.
  final Duration settle;
}
