// Plain `test`s, not `testWidgets`: they talk to a real loopback server,
// which the widget-test binding would replace with a fake HTTP client.
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tidy_log_sample/api/mock_server.dart';
import 'package:tidy_log_sample/demos/api_demo.dart';

import 'helpers.dart';

void main() {
  late MockServer server;
  late RecordingLogger logger;
  late ApiDemo api;

  setUpAll(() async => server = await MockServer.start(slowDelay: const Duration(milliseconds: 600)));
  tearDownAll(() => server.close());

  setUp(() {
    logger = RecordingLogger();
    final dio = Dio(
      BaseOptions(
        baseUrl: server.baseUri.toString(),
        connectTimeout: const Duration(seconds: 2),
        receiveTimeout: const Duration(milliseconds: 200),
      ),
    );
    api = ApiDemo(dio, logger);
  });

  group('successful calls', () {
    test('GET accounts returns the three accounts', () async {
      expect(await api.loadAccounts(), 'Loaded 3 accounts');
      expect(logger.records.single, (level: 'i', message: 'Loaded 3 accounts', tag: 'Api', error: null, stackTrace: null));
    });

    test('POST sign-in returns a token', () async {
      expect(await api.signIn(), 'Signed in');
      expect(logger.records.single.message, 'Signed in, token expires in 30 s');
    });
  });

  group('faulty calls', () {
    test('401 and 404 are logged as warnings with their status', () async {
      expect(await api.loadProfile(), 'Profile failed: 401');
      expect(await api.loadStatements(), 'Statements failed: 404');
      expect(logger.records.map((r) => (r.level, r.message)), [('w', 'Profile failed: 401'), ('w', 'Statements failed: 404')]);
    });

    test('500 is logged as an error with the DioException and its stack', () async {
      expect(await api.sendTransfer(), 'Transfer failed: 500');
      final record = logger.records.single;
      expect(record.level, 'e');
      expect(record.error, isA<DioException>().having((e) => e.response?.data, 'body', {
        'type': 2,
        'messages': ['Transfer service unavailable'],
      }));
      expect(record.stackTrace, isNotNull);
    });

    test('a slow answer ends in a receive timeout', () async {
      expect(await api.loadSlowReport(), 'Report failed: receiveTimeout');
      expect((logger.records.single.error! as DioException).type, DioExceptionType.receiveTimeout);
    });

    test('a truncated JSON body fails to decode', () async {
      final status = await api.loadBrokenJson();
      expect(status, startsWith('Accounts (broken JSON) failed:'));
      expect((logger.records.single.error! as DioException).error, isA<FormatException>());
    });

    test('a closed port fails without a response', () async {
      // Android and Linux refuse at once (connectionError); Windows retries
      // the SYN and gives up after the connect timeout.
      expect(await api.pingRefused(), matches(r'^Ping failed: (connectionError|connectionTimeout)$'));
      expect((logger.records.single.error! as DioException).response, isNull);
    });
  });
}
