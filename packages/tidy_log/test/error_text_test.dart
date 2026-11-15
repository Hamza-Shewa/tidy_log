import 'dart:io';

import 'package:dio/dio.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tidy_log/tidy_log.dart';
import 'package:tidy_log/src/flutter_error_formatter.dart';

DioException _dio(DioExceptionType type, {Object? error, int? status, RequestOptions? options}) {
  final request = options ?? RequestOptions(path: '/api/x');
  return DioException(
    requestOptions: request,
    type: type,
    error: error,
    response: status == null ? null : Response<Object?>(requestOptions: request, statusCode: status),
  );
}

void main() {
  late List<String> printed;

  setUp(() {
    printed = [];
    TidyLog.reset();
    TidyLog.configure(enabled: true, color: false, printer: printed.add, projectPackages: ['app']);
  });
  tearDown(TidyLog.reset);

  String errorLine(Object error) {
    printed.clear();
    TidyLog.e('call failed', error: error);
    return printed[1];
  }

  group('DioException', () {
    test('each type gets a few words instead of Dio\'s explanation', () {
      final timeouts = RequestOptions(
        path: '/x',
        connectTimeout: const Duration(seconds: 2),
        receiveTimeout: const Duration(milliseconds: 1500),
      );
      expect(errorLine(_dio(DioExceptionType.receiveTimeout, options: timeouts)), '    DioException · receive timeout (1,500 ms)');
      expect(errorLine(_dio(DioExceptionType.connectionTimeout, options: timeouts)), '    DioException · connect timeout (2 s)');
      expect(errorLine(_dio(DioExceptionType.badResponse, status: 500)), '    DioException · bad response 500');
      expect(errorLine(_dio(DioExceptionType.cancel)), '    DioException · cancelled');
      expect(errorLine(_dio(DioExceptionType.badCertificate)), '    DioException · bad certificate');
    });

    test('connection errors name the socket failure, without the OS error', () {
      final refused = SocketException('Connection refused', osError: const OSError('Connection refused', 111), port: 9);
      final lookup = SocketException("Failed host lookup: 'api.sample.invalid'", osError: const OSError('No address', 7));
      expect(errorLine(_dio(DioExceptionType.connectionError, error: refused)), '    DioException · connection refused');
      expect(errorLine(_dio(DioExceptionType.connectionError, error: lookup)), '    DioException · host lookup failed: api.sample.invalid');
    });

    test('an unknown error shows the wrapped error instead of "null"', () {
      final error = _dio(DioExceptionType.unknown, error: const FormatException('Unexpected end of input (at offset 19)'));
      expect(errorLine(error), '    DioException · FormatException: Unexpected end of input (at offset 19)');
    });
  });

  group('PlatformException', () {
    test('code and message, then the details', () {
      TidyLog.e('Card reader failed', error: PlatformException(code: 'UNAVAILABLE', message: 'Card reader is not connected.', details: {'retryable': true}));
      expect(printed, [
        'ERR Card reader failed',
        '    PlatformException(UNAVAILABLE): Card reader is not connected.',
        '    details  {retryable: true}',
      ]);
    });

    test('a Java stack becomes the first app frame and a summary', () {
      const stacktrace = '''
java.lang.IllegalStateException: Keystore entry missing
	at dev.tidylog.sample.MainActivity.handle(MainActivity.kt:35)
	at io.flutter.plugin.common.MethodChannel\$IncomingMethodCallHandler.onMessage(MethodChannel.java:267)
Caused by: java.io.IOException: decryption failed''';
      TidyLog.e('Keystore failed', error: PlatformException(code: 'error', message: 'Keystore entry missing', stacktrace: stacktrace));
      expect(printed, [
        'ERR Keystore failed',
        '    PlatformException(error): Keystore entry missing',
        '    native at dev.tidylog.sample.MainActivity.handle(MainActivity.kt:35)',
        '    ┊ … 1 frame hidden · caused by IOException: decryption failed',
      ]);
    });
  });

  test('an error passed as the message is described too (uncaught errors)', () {
    TidyLog.e(_dio(DioExceptionType.cancel), tag: 'uncaught');
    expect(printed.single, startsWith('ERR DioException · cancelled'));
  });

  test('errorText describes your own types and wins over the built-ins', () {
    TidyLog.configure(errorText: (e) => e is StateError ? 'state: ${e.message}' : null);
    expect(errorLine(StateError('no user')), '    state: no user');
    expect(errorLine(_dio(DioExceptionType.cancel)), '    DioException · cancelled', reason: 'null falls back');
  });

  test('error text is redacted like the message', () {
    expect(errorLine(StateError('token: abc123')), '    Bad state: token: ••••••••');
  });

  group('follow-on layout errors', () {
    FlutterErrorDetails details(String message) =>
        FlutterErrorDetails(exception: FlutterError(message), library: 'rendering library');

    test('are counted after a root error and summed up in one line', () {
      fakeAsync((async) {
        final formatter = FlutterErrorFormatter();
        formatter.present(details('Vertical viewport was given unbounded height.'));
        for (final name in ['RenderViewport#0c59b NEEDS-PAINT', 'RenderFlex#96b54 relayoutBoundary=up1 NEEDS-PAINT', 'RenderClipRect#111a3']) {
          formatter.present(details('RenderBox was not laid out: $name'));
          async.elapse(const Duration(milliseconds: 100));
        }
        expect(printed.where((l) => l.startsWith('ERR')), hasLength(1));

        async.elapse(const Duration(seconds: 1));
        expect(printed.first, startsWith('ERR Vertical viewport was given unbounded height.'));
        expect(printed.last, '    ┊ +3 follow-on errors hidden (RenderBox was not laid out)');
      });
    });

    test('a follow-on error with no root error before it is printed, without render ids', () {
      fakeAsync((async) {
        FlutterErrorFormatter().present(details('RenderBox was not laid out: RenderViewport#0c59b NEEDS-LAYOUT NEEDS-PAINT'));
        async.elapse(const Duration(seconds: 1));
        expect(printed.first, startsWith('ERR RenderBox was not laid out: RenderViewport'));
        expect(printed.first, isNot(contains('#0c59b')));
        expect(printed.where((l) => l.contains('follow-on')), isEmpty);
      });
    });

    test('a new root error closes the count first, so the summary stays under its root', () {
      fakeAsync((async) {
        final formatter = FlutterErrorFormatter();
        formatter.present(details('Vertical viewport was given unbounded height.'));
        formatter.present(details('RenderBox was not laid out: RenderViewport#0c59b'));
        formatter.present(details('A RenderFlex overflowed by 268 pixels on the right.'));
        async.elapse(const Duration(seconds: 1));

        final summary = printed.indexOf('    ┊ +1 follow-on error hidden (RenderBox was not laid out)');
        final overflow = printed.indexWhere((l) => l.startsWith('ERR A RenderFlex overflowed'));
        expect(summary, greaterThan(0));
        expect(summary, lessThan(overflow));
      });
    });
  });
}
