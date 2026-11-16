import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tidy_log/tidy_log.dart';

import 'fake_adapter.dart';

void main() {
  late List<String> printed;
  late List<DateTime> times;

  setUp(() {
    printed = [];
    times = [DateTime(2026, 11, 15, 15, 21, 9), DateTime(2026, 11, 15, 15, 21, 9, 1003)];
    TidyLog.reset();
    TidyLog.configure(enabled: true, color: false, printer: printed.add);
  });
  tearDown(TidyLog.reset);

  Dio dio(FakeAdapter adapter) => Dio(BaseOptions(baseUrl: 'http://10.0.0.1:4013'))
    ..httpClientAdapter = adapter
    ..interceptors.add(TidyDioInterceptor(clock: () => times.removeAt(0)));

  test('an error response prints one entry with status, timing, masked body and response', () async {
    final client = dio(FakeAdapter(status: 401, body: jsonEncode({'error': 'bad pin'})));
    await expectLater(
      client.post<Object?>('/api/Auth/Signin', data: {'userId': 1, 'pin': 12345678}),
      throwsA(isA<DioException>()),
    );
    expect(printed, [
      'POST /api/Auth/Signin  10.0.0.1:4013  401  1,003 ms · 15:21:09',
      '    body  {userId: 1, pin: ••••••••}',
      '    resp  {error: bad pin}',
    ]);
  });

  test('a transport failure prints ERR with a short reason', () async {
    final client = dio(
      FakeAdapter(error: const SocketException('Connection refused', osError: OSError('Connection refused', 111))),
    );
    await expectLater(client.get<Object?>('/api/ping'), throwsA(isA<DioException>()));
    expect(printed.single, 'GET /api/ping  10.0.0.1:4013  ERR connection refused  1,003 ms · 15:21:09');
  });

  test('logBodies: false keeps bodies out of the log', () async {
    final client = Dio(BaseOptions(baseUrl: 'http://h'))
      ..httpClientAdapter = FakeAdapter(body: '{"secret":"x"}')
      ..interceptors.add(TidyDioInterceptor(logBodies: false, clock: () => times.removeAt(0)));
    await client.post<Object?>('/a', data: {'a': 1});
    expect(printed, hasLength(1));
    expect(printed.single, startsWith('POST /a  h  200'));
  });
}
