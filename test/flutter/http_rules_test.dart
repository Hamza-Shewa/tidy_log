import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tidy_log/tidy_log.dart';

import 'fake_adapter.dart';

/// A head line for a plain 200: no ✕ or ! mark after the status.
final _plain200 = RegExp(r'^POST +/api/Auth/OpenSession +200  ');

void main() {
  late List<String> printed;

  setUp(() {
    printed = [];
    TidyLog.reset();
    TidyLog.configure(enabled: true, color: false, printer: printed.add);
  });
  tearDown(TidyLog.reset);

  /// One call through a client answering [status] with [body]; returns what
  /// was printed. Errors from Dio (4xx/5xx) are expected and ignored.
  Future<List<String>> call(
    Object body, {
    int status = 200,
    List<ResponseRule>? rules,
    HttpBodies? bodies,
    String path = '/api/Auth/OpenSession',
    String contentType = 'application/json',
  }) async {
    final dio = Dio(BaseOptions(baseUrl: 'http://h'))
      ..httpClientAdapter = FakeAdapter(
        status: status,
        body: body is String ? body : jsonEncode(body),
        contentType: contentType,
      )
      ..interceptors.add(TidyDioInterceptor(rules: rules, bodies: bodies));
    try {
      await dio.post<Object?>(path, data: {'pin': '1234'});
    } on DioException {
      // 4xx/5xx; the log line is what is under test.
    }
    return printed;
  }

  final success = ResponseRule.field('success', {
    true: HttpOutcome.success,
    false: HttpOutcome.error,
  }, message: 'message');

  group('ResponseRule.field', () {
    test('a 200 with success: false is logged as an error with its message', () async {
      final out = await call({'success': false, 'message': 'Insufficient balance'}, rules: [success]);
      expect(out.first, contains('200 ✕'));
      expect(out[1], '    ✕ Insufficient balance');
      expect(out[2], '    rule  success = false → error');
    });

    test('a 200 with success: true stays a plain success line', () async {
      final out = await call({'success': true, 'message': 'ok'}, rules: [success]);
      expect(out.first, matches(_plain200));
      expect(out[1], '    · ok');
      expect(out.where((l) => l.contains('rule')), isEmpty, reason: 'a success needs no rule line');
    });

    test('enum values match case-insensitively; the message can be the first item of a list', () async {
      final rule = ResponseRule.field('response_type', {
        'SUCCESS': HttpOutcome.success,
        'WARNING': HttpOutcome.warning,
        'ERROR': HttpOutcome.error,
      }, message: 'messages');
      final out = await call(
        {
          'response_type': 'warning',
          'messages': ['Session expires in 2 minutes', 'second'],
        },
        rules: [rule],
      );
      expect(out.first, contains('200 !'));
      expect(out[1], '    ! Session expires in 2 minutes');
      expect(out[2], '    rule  response_type = "warning" → warning');
    });

    test('a number in the body matches a number or numeric text in the rule', () async {
      final rule = ResponseRule.field('type', {'2': HttpOutcome.error}, message: 'messages');
      final out = await call(
        {
          'type': 2,
          'messages': ['unvalid api sign'],
        },
        rules: [rule],
      );
      expect(out.first, contains('200 ✕'));
      expect(out, contains('    ✕ unvalid api sign'));
    });

    test('a dotted path reaches into nested objects and lists', () async {
      final rule = ResponseRule.field('meta.errors.0.code', {
        'E_LIMIT': HttpOutcome.error,
      }, message: 'meta.errors.0.text');
      final out = await call(
        {
          'meta': {
            'errors': [
              {'code': 'E_LIMIT', 'text': 'Daily limit reached'},
            ],
          },
        },
        rules: [rule],
      );
      expect(out.first, contains('200 ✕'));
      expect(out, contains('    ✕ Daily limit reached'));
    });

    test('a JSON body that arrives as text is decoded for the rule', () async {
      final out = await call(
        '{"success": false, "message": "plain text body"}',
        rules: [success],
        contentType: 'text/plain',
      );
      expect(out.first, contains('200 ✕'));
      expect(out, contains('    ✕ plain text body'));
    });

    test('an unlisted value uses otherwise, or leaves the status colour when there is none', () async {
      final strict = ResponseRule.field('status', {'OK': HttpOutcome.success}, otherwise: HttpOutcome.warning);
      expect((await call({'status': 'PENDING'}, rules: [strict])).first, contains('200 !'));

      printed.clear();
      final loose = ResponseRule.field('status', {'OK': HttpOutcome.success});
      final out = await call({'status': 'PENDING'}, rules: [loose]);
      expect(out.first, matches(_plain200));
      expect(out.where((l) => l.contains('rule')), isEmpty);
    });

    test('when limits a rule to some requests', () async {
      final rule = ResponseRule.field('success', {
        false: HttpOutcome.error,
      }, when: (o) => o.path.startsWith('/api/Auth'));
      expect((await call({'success': false}, rules: [rule], path: '/api/other')).first, isNot(contains('✕')));
      printed.clear();
      expect((await call({'success': false}, rules: [rule])).first, contains('200 ✕'));
    });

    test('rules also run on error responses: a 400 can be just a warning', () async {
      final rule = ResponseRule.field('response_type', {'WARNING': HttpOutcome.warning});
      final out = await call({'response_type': 'WARNING'}, status: 400, rules: [rule]);
      expect(out.first, contains('400 !'));
    });

    test('a missing field or a non-JSON body gives no verdict', () async {
      expect((await call({'other': 1}, rules: [success])).first, matches(_plain200));
      printed.clear();
      expect(
        (await call('<html>oops</html>', rules: [success], contentType: 'text/html')).first,
        isNot(contains('rule')),
      );
    });

    test('the first rule with a verdict wins', () async {
      final first = ResponseRule.field('code', {1: HttpOutcome.warning});
      final out = await call({'code': 1, 'success': false}, rules: [first, success]);
      expect(out.first, contains('200 !'));
    });

    test('the verdict message is redacted', () async {
      final rule = ResponseRule.field('ok', {false: HttpOutcome.error}, message: 'detail');
      final out = await call({'ok': false, 'detail': 'bad token: abc'}, rules: [rule]);
      expect(out, contains('    ✕ bad token: ••••••••'));
    });
  });

  group('ResponseRule.custom', () {
    test('decides from the whole response', () async {
      final rule = ResponseRule.custom(
        (r) => (r.data as Map)['errors'] != null
            ? const RuleVerdict(HttpOutcome.error, message: 'has errors', reason: 'errors present')
            : null,
      );
      final out = await call(
        {
          'errors': ['x'],
        },
        rules: [rule],
      );
      expect(out.first, contains('200 ✕'));
      expect(out[1], '    ✕ has errors');
      expect(out[2], '    rule  errors present');
    });

    test('a rule that throws is reported and the call is still logged', () async {
      final broken = ResponseRule.custom((r) => throw StateError('rule bug'));
      final out = await call({'success': false}, rules: [broken, success]);
      expect(out.first, startsWith('WRN Response rule failed: Bad state: rule bug'));
      expect(out.firstWhere((l) => l.startsWith('POST')), contains('200 ✕'), reason: 'the next rule still runs');
    });
  });

  test('global rules from configure apply when the interceptor has none', () async {
    TidyLog.configure(httpRules: [success]);
    expect((await call({'success': false})).first, contains('200 ✕'));
    printed.clear();
    expect(
      (await call({'success': false}, rules: const [])).first,
      isNot(contains('✕')),
      reason: 'an explicit empty list means no rules',
    );
  });

  group('httpBodies', () {
    test('always (the default) prints body and resp for a success', () async {
      final out = await call({'ok': true});
      expect(out.first, matches(_plain200));
      expect(out.skip(1), ['    body  pin: ••••••••', '    resp  ok: true']);
    });

    test('onFailure hides them for a success and shows them for a failure', () async {
      TidyLog.configure(httpBodies: HttpBodies.onFailure);
      expect(await call({'ok': true}), hasLength(1));

      printed.clear();
      expect(await call({'error': 'nope'}, status: 500), hasLength(3));

      printed.clear();
      final flagged = await call({'success': false, 'message': 'no'}, rules: [success]);
      expect(flagged.where((l) => l.startsWith('    resp')), hasLength(1), reason: 'a rule-flagged 200 is a failure');
    });

    test('the interceptor setting wins over the global one; never prints one line', () async {
      TidyLog.configure(httpBodies: HttpBodies.always);
      expect(await call({'error': 'nope'}, status: 500, bodies: HttpBodies.never), hasLength(1));
    });
  });

  test('the outcome sets the level, so minLevel can hide successful calls', () async {
    TidyLog.configure(minLevel: Level.warning);
    expect(await call({'ok': true}), isEmpty);
    expect((await call({'success': false}, rules: [success])).first, contains('200 ✕'));
  });
}
