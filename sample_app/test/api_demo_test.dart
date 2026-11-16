// Plain `test`s, not `testWidgets`: they talk to a real loopback server,
// which the widget-test binding would replace with a fake HTTP client.
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tidy_log/tidy_log.dart';
import 'package:tidy_log_sample/api/mock_server.dart';
import 'package:tidy_log_sample/api/response_rules.dart';
import 'package:tidy_log_sample/demos/api_demo.dart';

import 'helpers.dart';

void main() {
  late MockServer server;
  late RecordingLogger logger;
  late ApiDemo api;

  setUpAll(() async => server = await MockServer.start(slowDelay: const Duration(milliseconds: 600)));
  tearDownAll(() => server.close());

  /// An [ApiDemo] on the mock server. Only the timeout test shortens [receiveTimeout]; a slow test machine must not
  /// turn the other calls into timeouts.
  ApiDemo apiWith({Duration receiveTimeout = const Duration(seconds: 10)}) => ApiDemo(
    Dio(
      BaseOptions(
        baseUrl: server.baseUri.toString(),
        connectTimeout: const Duration(seconds: 2),
        receiveTimeout: receiveTimeout,
      ),
    ),
    logger,
  );

  setUp(() {
    logger = RecordingLogger();
    api = apiWith();
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
      // The server answers after 600 ms.
      final impatient = apiWith(receiveTimeout: const Duration(milliseconds: 200));
      expect(await impatient.loadSlowReport(), 'Report failed: receiveTimeout');
      expect((logger.records.single.error! as DioException).type, DioExceptionType.receiveTimeout);
    });

    test('a truncated JSON body fails to decode', () async {
      final status = await api.loadBrokenJson();
      expect(status, startsWith('Accounts (broken JSON) failed:'));
      expect((logger.records.single.error! as DioException).error, isA<FormatException>());
    });

    test('a closed port fails without a response', () async {
      // A port that was free a moment ago, rather than assuming nothing listens on port 9.
      final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = probe.port;
      await probe.close();
      // Android and Linux refuse at once (connectionError); Windows retries
      // the SYN and gives up after the connect timeout.
      expect(await api.pingRefused(port: port), matches(r'^Ping failed: (connectionError|connectionTimeout)$'));
      expect((logger.records.single.error! as DioException).response, isNull);
    });
  });

  group('"200 for everything" endpoints', () {
    test('the app still reads the real result from the body', () async {
      expect(await api.loadBalance(), 'Balance: 1250.500');
      expect(await api.payBill(), 'Payment refused: Insufficient balance');
      expect(await api.checkSession(), 'Session: WARNING');
      expect(await api.openSession(), 'OpenSession refused: type 2');
      expect(await api.activateCard(), 'Card activation failed: 400');
    });

    test('the sample response rules make each log line agree with the body', () async {
      final printed = <String>[];
      TidyLog.reset();
      TidyLog.configure(enabled: true, color: false, printer: printed.add, httpRules: sampleResponseRules);
      addTearDown(TidyLog.reset);
      final dio = Dio(BaseOptions(baseUrl: server.baseUri.toString()))..interceptors.add(TidyDioInterceptor());
      final tidyApi = ApiDemo(dio, logger);

      await tidyApi.loadBalance();
      await tidyApi.payBill();
      await tidyApi.checkSession();
      await tidyApi.openSession();
      await tidyApi.activateCard();
      await tidyApi.loadAccounts();

      // Read the fields, not the column layout, so restyling the entry does not break this test.
      final entries = httpEntries(printed);
      expect([for (final e in entries) (e.method, e.path, e.status)], [
        ('GET', '/api/balance', '200'),
        ('POST', '/api/wallet/pay', '200'),
        ('GET', '/api/session', '200'),
        ('POST', '/api/Auth/OpenSession', '200'),
        ('POST', '/api/cards/activate', '400'),
        ('GET', '/api/accounts', '200'),
      ]);
      expect([for (final e in entries) e.verdict], [
        '· OK',
        '✕ Insufficient balance',
        '! Session expires in 2 minutes',
        '✕ unvalid api sign',
        '✕ Card is blocked',
        null,
      ]);
      for (final e in entries) {
        expect(e.lines.join('\n'), contains(server.baseUri.authority), reason: 'every entry names the host');
      }
      expect(printed.map((l) => l.trim()), contains('rule  type = 2 → error'));
    });
  });
}

typedef HttpEntry = ({String method, String path, String status, String? verdict, List<String> lines});

/// The HTTP entries in [printed]: a line that starts with the method, path and status, and the indented lines under
/// it. The verdict is the first `· text`, `✕ text` or `! text` in the entry, wherever the layout puts it.
List<HttpEntry> httpEntries(List<String> printed) {
  final head = RegExp(r'^(GET|POST|PUT|PATCH|DELETE)\s+(\S+)\s+(\d{3}|ERR)\b');
  final verdict = RegExp(r'([·✕!]) (\S.*?)(?=\s{2}|$)');
  final groups = <List<String>>[];
  for (final line in printed.expand((l) => l.split('\n'))) {
    if (head.hasMatch(line)) {
      groups.add([line]);
    } else if (groups.isNotEmpty && line.startsWith(' ')) {
      groups.last.add(line);
    }
  }
  return [
    for (final lines in groups)
      if (head.firstMatch(lines.first) case final m?)
        (
          method: m[1]!,
          path: m[2]!,
          status: m[3]!,
          verdict: [for (final l in lines) ?verdict.firstMatch(l)].map((v) => '${v[1]} ${v[2]}').firstOrNull,
          lines: lines,
        ),
  ];
}
