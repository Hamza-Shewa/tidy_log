import 'package:flutter/material.dart';

import '../pages/broken_pages.dart';
import 'scenario.dart';

ScenarioAction _open(Widget page) => (context, _) {
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  return null;
};

/// Every scenario, in screen order and "Run all" order.
final List<Scenario> scenarios = [
  // Log lines
  Scenario(
    id: 'log-levels',
    group: ScenarioGroup.logs,
    title: 'Log each level',
    expected: 'DBG / INF / WRN / ERR lines; PIN and password masked',
    run: (_, d) => d.logs.levels(),
  ),
  Scenario(
    id: 'log-repeats',
    group: ScenarioGroup.logs,
    title: 'Log repeats',
    expected: '25 identical lines → one line ×25; 8 numbered lines kept',
    run: (_, d) => d.logs.repeats(),
  ),
  Scenario(
    id: 'log-raw-prints',
    group: ScenarioGroup.logs,
    title: 'Raw debugPrint lines',
    expected: 'Unstyled Dart prints, token masked by the wrapper',
    run: (_, d) => d.logs.rawPrints(),
  ),

  // Dart errors (thrown from a tap handler unless noted)
  Scenario(
    id: 'dart-null-check',
    group: ScenarioGroup.dart,
    title: 'Null check in a tap handler',
    expected: 'Null check operator used on a null value',
    run: (_, d) => '${d.dart.nullCheck()}',
  ),
  Scenario(
    id: 'dart-bad-cast',
    group: ScenarioGroup.dart,
    title: 'Bad cast from JSON',
    expected: "type 'String' is not a subtype of type 'num' in type cast",
    run: (_, d) => '${d.dart.badCast()}',
  ),
  Scenario(
    id: 'dart-range-error',
    group: ScenarioGroup.dart,
    title: 'List index out of range',
    expected: 'RangeError (length): Invalid value',
    run: (_, d) => d.dart.rangeError(),
  ),
  Scenario(
    id: 'dart-state-error',
    group: ScenarioGroup.dart,
    title: '.first on an empty list',
    expected: 'Bad state: No element',
    run: (_, d) => d.dart.stateError(),
  ),
  Scenario(
    id: 'dart-assert',
    group: ScenarioGroup.dart,
    title: 'Failed assert',
    expected: 'Failed assertion: … Transfer amount must be positive',
    run: (_, d) {
      d.dart.failedAssert();
      return null;
    },
  ),
  Scenario(
    id: 'dart-caught-format',
    group: ScenarioGroup.dart,
    title: 'Caught FormatException, logged',
    expected: 'ERR line pointing at _parseAmount in lib/demos/',
    run: (_, d) => d.dart.caughtFormatError(),
  ),
  Scenario(
    id: 'dart-uncaught-async',
    group: ScenarioGroup.dart,
    title: 'Uncaught async error',
    expected: 'TimeoutException via PlatformDispatcher.onError',
    run: (_, d) => d.dart.uncaughtAsync(),
  ),
  Scenario(
    id: 'dart-unknown-route',
    group: ScenarioGroup.dart,
    title: 'Push an unknown named route',
    expected: 'Could not find a generator for route "/transfers/42"',
    run: (context, _) {
      Navigator.of(context).pushNamed<void>('/transfers/42');
      return null;
    },
  ),

  // Build and layout errors (each opens a broken page)
  Scenario(
    id: 'layout-null-in-build',
    group: ScenarioGroup.layout,
    title: 'Null in build (red screen)',
    expected: 'Null check operator, caught by widgets library',
    run: _open(const NullInBuildPage()),
    opensPage: true,
    settle: const Duration(milliseconds: 1500),
  ),
  Scenario(
    id: 'layout-overflow',
    group: ScenarioGroup.layout,
    title: 'Row overflow',
    expected: 'A RenderFlex overflowed by … pixels on the right',
    run: _open(const OverflowPage()),
    opensPage: true,
    settle: const Duration(milliseconds: 1500),
  ),
  Scenario(
    id: 'layout-unbounded-height',
    group: ScenarioGroup.layout,
    title: 'ListView in a Column',
    expected: 'Vertical viewport was given unbounded height',
    run: _open(const UnboundedHeightPage()),
    opensPage: true,
    settle: const Duration(milliseconds: 1500),
  ),
  Scenario(
    id: 'layout-unbounded-width',
    group: ScenarioGroup.layout,
    title: 'TextField in a Row',
    expected: 'An InputDecorator … cannot have an unbounded width',
    run: _open(const UnboundedWidthFieldPage()),
    opensPage: true,
    settle: const Duration(milliseconds: 1500),
  ),
  Scenario(
    id: 'layout-parent-data',
    group: ScenarioGroup.layout,
    title: 'Expanded inside a Stack',
    expected: 'Incorrect use of ParentDataWidget',
    run: _open(const WrongParentDataPage()),
    opensPage: true,
    settle: const Duration(milliseconds: 1500),
  ),
  Scenario(
    id: 'layout-broken-image',
    group: ScenarioGroup.layout,
    title: 'Network image that cannot load',
    expected: 'Exception caught by image resource service',
    run: _open(const BrokenImagePage()),
    opensPage: true,
    settle: const Duration(milliseconds: 2000),
  ),

  // API calls (local mock server unless noted)
  Scenario(
    id: 'api-accounts',
    group: ScenarioGroup.api,
    title: 'GET accounts (200)',
    expected: 'GET /api/accounts  200',
    run: (_, d) => d.api.loadAccounts(),
  ),
  Scenario(
    id: 'api-sign-in',
    group: ScenarioGroup.api,
    title: 'POST sign-in (200)',
    expected: 'POST /api/Auth/Signin  200; pin, password and token masked',
    run: (_, d) => d.api.signIn(),
  ),
  Scenario(
    id: 'api-profile-401',
    group: ScenarioGroup.api,
    title: 'GET profile (401)',
    expected: 'GET /api/profile  401',
    run: (_, d) => d.api.loadProfile(),
  ),
  Scenario(
    id: 'api-statements-404',
    group: ScenarioGroup.api,
    title: 'GET statements (404)',
    expected: 'GET /api/statements  404',
    run: (_, d) => d.api.loadStatements(),
  ),
  Scenario(
    id: 'api-transfer-500',
    group: ScenarioGroup.api,
    title: 'POST transfer (500)',
    expected: 'POST /api/transfers  500; otp masked; ERR with DioException',
    run: (_, d) => d.api.sendTransfer(),
  ),
  Scenario(
    id: 'api-timeout',
    group: ScenarioGroup.api,
    title: 'Receive timeout',
    expected: 'GET /api/slow  receiveTimeout',
    run: (_, d) => d.api.loadSlowReport(),
    settle: const Duration(milliseconds: 1800),
  ),
  Scenario(
    id: 'api-broken-json',
    group: ScenarioGroup.api,
    title: 'Malformed JSON body',
    expected: 'GET /api/broken-json  FormatException',
    run: (_, d) => d.api.loadBrokenJson(),
  ),
  Scenario(
    id: 'api-refused',
    group: ScenarioGroup.api,
    title: 'Connection refused',
    expected: 'GET 127.0.0.1:9/api/ping  connection refused',
    run: (_, d) => d.api.pingRefused(),
  ),
  Scenario(
    id: 'api-dns',
    group: ScenarioGroup.api,
    title: 'Unknown host',
    expected: 'GET api.sample.invalid  failed host lookup',
    run: (_, d) => d.api.pingUnknownHost(),
    settle: const Duration(milliseconds: 2500),
  ),

  // Platform channels (Android side in MainActivity.kt)
  Scenario(
    id: 'platform-battery',
    group: ScenarioGroup.platform,
    title: 'Battery level (success)',
    expected: 'INF Battery at N%; native I/SampleNative line',
    run: (_, d) => d.platform.batteryLevel(),
  ),
  Scenario(
    id: 'platform-error',
    group: ScenarioGroup.platform,
    title: 'Native result.error',
    expected: 'PlatformException(UNAVAILABLE, Card reader is not connected.)',
    run: (_, d) => d.platform.readCard(),
  ),
  Scenario(
    id: 'platform-native-throw',
    group: ScenarioGroup.platform,
    title: 'Native handler throws',
    expected: 'E/MethodChannel#… Java stack; PlatformException(error, …)',
    run: (_, d) => d.platform.openKeystore(),
  ),
  Scenario(
    id: 'platform-not-implemented',
    group: ScenarioGroup.platform,
    title: 'Method not implemented natively',
    expected: 'Uncaught MissingPluginException(No implementation found …)',
    run: (_, d) => d.platform.scanFingerprint(),
  ),
  Scenario(
    id: 'platform-missing-plugin',
    group: ScenarioGroup.platform,
    title: 'Channel with no plugin',
    expected: 'Uncaught MissingPluginException on not_registered',
    run: (_, d) => d.platform.pingMissingPlugin(),
  ),
  Scenario(
    id: 'platform-unimplemented',
    group: ScenarioGroup.platform,
    title: 'Platform interface not implemented',
    expected: 'UnimplementedError: authenticate() has not been implemented.',
    run: (_, d) => d.platform.authenticate(),
  ),
  Scenario(
    id: 'platform-native-logs',
    group: ScenarioGroup.platform,
    title: 'Native logcat lines',
    expected: 'V/D/I/W/E from Kotlin, a Java stack, ×30 repeats',
    run: (_, d) => d.platform.nativeLogs(),
  ),
];
