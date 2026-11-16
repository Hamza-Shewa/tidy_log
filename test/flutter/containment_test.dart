import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tidy_log/src/flutter/flutter_error_formatter.dart';
import 'package:tidy_log/tidy_log.dart';

import 'fake_adapter.dart';

/// An object whose `toString()` throws, like a half-initialised model.
final class _Unprintable {
  @override
  String toString() => throw UnsupportedError('no text');
}

void main() {
  late List<String> printed;
  late List<String> fallback;
  late DebugPrintCallback savedDebugPrint;

  setUp(() {
    printed = [];
    fallback = [];
    savedDebugPrint = debugPrint;
    debugPrint = (message, {wrapWidth}) => fallback.add(message ?? '');
    TidyLog.reset();
    TidyLog.configure(enabled: true, color: false, printer: printed.add);
  });

  tearDown(() {
    debugPrint = savedDebugPrint;
    TidyLog.reset();
  });

  void throwingPrinter(String line) => throw StateError('printer bug');

  group('the logger never throws into the app', () {
    test('a printer that throws gives one fallback line', () {
      TidyLog.configure(printer: throwingPrinter);
      expect(() => TidyLog.e('boom', stackTrace: StackTrace.current), returnsNormally);
      expect(fallback, ['tidy_log: could not log (StateError)']);
    });

    test('a message whose toString() throws gives one fallback line', () {
      expect(() => TidyLog.i(_Unprintable()), returnsNormally);
      expect(() => TidyLog.w('saving', error: _Unprintable()), returnsNormally);
      expect(printed, isEmpty);
      expect(fallback, ['tidy_log: could not log (UnsupportedError)', 'tidy_log: could not log (UnsupportedError)']);
    });

    test('an errorText hook that throws falls back to the built-in text', () {
      TidyLog.configure(errorText: (error) => throw StateError('hook bug'));
      TidyLog.w('careful', error: StateError('x'));
      expect(printed, ['WRN careful', '    Bad state: x']);
      expect(fallback, isEmpty);
    });

    test('a debugPrint that logs through TidyLog does not loop on a failure', () {
      TidyLog.configure(printer: throwingPrinter);
      debugPrint = (message, {wrapWidth}) {
        fallback.add(message ?? '');
        TidyLog.i('echo: $message');
      };
      expect(() => TidyLog.i('hi'), returnsNormally);
      expect(fallback, ['tidy_log: could not log (StateError)']);
    });
  });

  group('Flutter errors', () {
    FlutterErrorDetails details({Object? exception, DiagnosticsNode? context, InformationCollector? info}) =>
        FlutterErrorDetails(
          exception: exception ?? FlutterError('Login failed: password=hunter2\nRetry with token=abc123.'),
          library: 'widgets library',
          context: context,
          informationCollector: info,
        );

    test('a secret is masked in the first report, the context, the notes and "thrown again"', () {
      final formatter = FlutterErrorFormatter();
      final error = details(context: ErrorDescription('while saving password=hunter2'));
      formatter.present(error);
      formatter.present(error);

      expect(printed.last, endsWith('· thrown again'));
      expect(printed.join('\n'), isNot(contains('hunter2')));
      expect(printed.join('\n'), isNot(contains('abc123')));
      expect(printed.first, startsWith('ERR Login failed: password=••••••••'));
    });

    test('an informationCollector that throws still prints the error', () {
      FlutterErrorFormatter().present(details(info: () => throw StateError('collector bug')));
      expect(printed.first, startsWith('ERR Login failed: password=••••••••'));
      expect(fallback, isEmpty);
    });

    test('a context whose description throws still prints the error', () {
      FlutterErrorFormatter().present(details(context: _ThrowingNode()));
      expect(printed.first, startsWith('ERR Login failed'));
    });

    test('an exception whose toString() throws gives one fallback line', () {
      expect(() => FlutterErrorFormatter().present(details(exception: _Unprintable())), returnsNormally);
      expect(printed, isEmpty);
      expect(fallback, hasLength(1));
      expect(fallback.single, startsWith('tidy_log: could not log ('));
    });
  });

  group('Dio calls', () {
    late List<DateTime> times;

    setUp(() => times = [DateTime(2026, 11, 15, 15, 21, 9), DateTime(2026, 11, 15, 15, 21, 9, 1003)]);

    Dio dio(FakeAdapter adapter, {List<ResponseRule>? rules}) => Dio(BaseOptions(baseUrl: 'http://h'))
      ..httpClientAdapter = adapter
      ..interceptors.add(
        TidyDioInterceptor(rules: rules, clock: () => times.isEmpty ? DateTime(2026) : times.removeAt(0)),
      );

    test('a 200 still arrives as a Response when logging it fails', () async {
      TidyLog.configure(printer: throwingPrinter);
      final response = await dio(FakeAdapter()).get<Object?>('/a');
      expect(response.statusCode, 200);
      expect(fallback, ['tidy_log: could not log (StateError)']);
    });

    test('a failed call keeps its own DioException when logging it fails', () async {
      TidyLog.configure(printer: throwingPrinter);
      final client = dio(
        FakeAdapter(error: const SocketException('Connection refused', osError: OSError('Connection refused', 111))),
      );
      await expectLater(
        client.get<Object?>('/a'),
        throwsA(isA<DioException>().having((e) => e.error, 'error', isA<SocketException>())),
      );
    });

    test('a URL with a non-UTF-8 escape does not fail the call', () async {
      final response = await dio(FakeAdapter()).get<Object?>('/search?name=Jos%E9');
      expect(response.statusCode, 200);
    });

    test('request options with an unmodifiable extra map are logged with timing', () async {
      final client = dio(FakeAdapter());
      final response = await client.fetch<Object?>(RequestOptions(baseUrl: 'http://h', path: '/a', extra: const {}));
      expect(response.statusCode, 200);
      expect(printed.single, matches(RegExp(r'^GET +/a +200 +1,003 ms  15:21:09  h$')));
    });

    test('the start time is not written into extra', () async {
      final response = await dio(FakeAdapter()).get<Object?>('/a');
      expect(response.requestOptions.extra, isEmpty);
    });

    test('a failing rule warns once per rule, and the call is logged every time', () async {
      final broken = ResponseRule.custom((r) => throw StateError('rule bug'));
      final client = dio(FakeAdapter(), rules: [broken]);
      await client.get<Object?>('/a');
      await client.get<Object?>('/a');
      expect(printed.where((l) => l.startsWith('WRN Response rule failed')), hasLength(1));
      expect(printed.where((l) => l.startsWith('GET')), hasLength(2));
    });

    test('a failing rule with an errorText hook that throws still lets the call through', () async {
      TidyLog.configure(errorText: (error) => throw StateError('hook bug'));
      final broken = ResponseRule.custom((r) => throw ArgumentError('rule bug'));
      final response = await dio(FakeAdapter(), rules: [broken]).get<Object?>('/a');
      expect(response.statusCode, 200);
      expect(printed.first, startsWith('WRN Response rule failed: Invalid argument(s): rule bug'));
    });
  });
}

/// A diagnostics node whose description throws.
final class _ThrowingNode extends DiagnosticsNode {
  _ThrowingNode() : super(name: null);

  @override
  String toDescription({TextTreeConfiguration? parentConfiguration}) => throw StateError('description bug');

  @override
  List<DiagnosticsNode> getChildren() => const [];

  @override
  List<DiagnosticsNode> getProperties() => const [];

  @override
  Object? get value => null;
}
