import 'package:flutter_test/flutter_test.dart';
import 'package:tidy_log/src/core.dart';

const _styled = Renderer(includeSource: false);
const _plain = Renderer(color: false);

/// Where the status starts: a 7-wide method column, a 46-wide path column,
/// then two spaces.
const _statusColumn = 7 + 46 + 2;

/// The ANSI code the status number is painted with.
String _statusCode(Entry entry, String status) {
  final line = _styled.render(entry).first;
  final match = RegExp('\x1B\\[([0-9;]+)m$status\x1B\\[0m').firstMatch(line);
  expect(match, isNotNull, reason: 'status $status not found as its own span in $line');
  return match![1]!;
}

void main() {
  group('status colour by class', () {
    for (final (status, code, name) in [
      (200, '1;32', 'green'),
      (204, '1;32', 'green'),
      (304, '1;36', 'cyan'),
      (401, '33', 'yellow'),
      (404, '33', 'yellow'),
      (500, '1;31', 'red'),
      (503, '1;31', 'red'),
    ]) {
      test('$status is $name', () {
        expect(_statusCode(httpEntry(method: 'GET', url: '/a', status: status), '$status'), code);
      });
    }
  });

  group('an outcome from a response rule', () {
    test('turns a 200 red, marks it ✕ and shows the reason and rule on their own lines', () {
      final entry = httpEntry(
        method: 'post',
        url: 'http://10.0.2.2:4013/api/Auth/OpenSession',
        status: 200,
        outcome: HttpOutcome.error,
        verdict: 'unvalid api sign',
        rule: 'type = 2 → error',
        response: {'type': 2},
      );
      expect(_statusCode(entry, '200'), '1;31');
      final lines = _plain.render(entry);
      expect(lines.first, startsWith('POST   /api/Auth/OpenSession '));
      expect(lines.first.substring(_statusColumn, _statusColumn + 5), '200 ✕');
      expect(lines.skip(1), ['    ✕ unvalid api sign', '    rule  type = 2 → error', '    resp  type: 2']);
    });

    test('a warning is yellow with "!"; a success verdict is a dim note and its rule is not repeated', () {
      final warning = httpEntry(
        method: 'GET',
        url: '/s',
        status: 200,
        outcome: HttpOutcome.warning,
        verdict: 'expires soon',
      );
      expect(_statusCode(warning, '200'), '33');
      expect(_plain.render(warning).last, '    ! expires soon');

      final ok = httpEntry(
        method: 'GET',
        url: '/s',
        status: 400,
        outcome: HttpOutcome.success,
        verdict: 'validated',
        rule: 'type = 1 → success',
      );
      expect(_statusCode(ok, '400'), '1;32', reason: 'the rule wins over the status class');
      expect(_plain.render(ok).skip(1), ['    · validated']);
    });

    test('a long or multi-line verdict is shortened to one line', () {
      final entry = httpEntry(
        method: 'GET',
        url: '/s',
        status: 200,
        outcome: HttpOutcome.error,
        verdict: 'line one\n${'x' * 200}',
      );
      final reason = _plain.render(entry).last;
      expect(reason, startsWith('    ✕ line one x'));
      expect(reason, endsWith('…'));
      expect(reason.length, lessThan(120));
    });
  });

  group('layout', () {
    test('method, path, status, duration, time and host sit in fixed columns', () {
      final get = _plain.render(
        httpEntry(method: 'GET', url: 'http://h:1/api/Auth/SoftOtp', status: 200, durationMs: 669, time: '10:19:25'),
      );
      final post = _plain.render(
        httpEntry(
          method: 'POST',
          url: 'http://h:1/api/Inbox/UnReadMessagesCount?type=1',
          status: 404,
          durationMs: 52,
          time: '10:19:26',
        ),
      );
      for (final line in [get.first, post.first]) {
        expect(line.indexOf('/api'), 7);
        expect(line.substring(_statusColumn, _statusColumn + 3), anyOf('200', '404'));
        expect(line.indexOf(' ms'), _statusColumn + 5 + 9 - 3, reason: 'durations are right-aligned');
        expect(line, endsWith('  h:1'));
      }
      expect(get.first.indexOf('10:19:25'), post.first.indexOf('10:19:26'));
    });

    test('a transport error puts ERR in the status column and the reason on its own line', () {
      final lines = _plain.render(
        httpEntry(method: 'GET', url: 'http://h:1/a', error: 'connection refused', durationMs: 3),
      );
      expect(lines.first.substring(_statusColumn, _statusColumn + 3), 'ERR');
      expect(lines.skip(1), ['    ✕ connection refused']);
    });

    test('empty bodies are left out', () {
      final lines = _plain.render(
        httpEntry(method: 'GET', url: '/a', status: 200, body: <String, Object?>{}, response: ''),
      );
      expect(lines, hasLength(1));
    });

    test('bodies show one field per line, nested values indented, under an aligned label', () {
      final lines = _plain.render(
        httpEntry(
          method: 'POST',
          url: '/api/Auth/Signin',
          status: 200,
          body: {'userName': '218900000000', 'pin': '••••••••'},
          response: {
            'content': {'validTo': '2032-07-30T16:19:26Z', 'refreshToken': '', 'creds': 17},
            'type': 1,
            'messages': <Object?>[],
            'accounts': [
              {'accId': 1, 'nickName': 'Main'},
              {'accId': 2, 'nickName': 'Savings'},
            ],
          },
        ),
      );
      expect(lines.skip(1), [
        '    body  userName: 218900000000',
        '          pin: ••••••••',
        '    resp  content:',
        '            validTo: 2032-07-30T16:19:26Z',
        '            refreshToken: ""',
        '            creds: 17',
        '          type: 1',
        '          messages: []',
        '          accounts:',
        '            - accId: 1',
        '              nickName: Main',
        '            - accId: 2',
        '              nickName: Savings',
      ]);
    });

    test('a JSON text body is decoded; other text keeps its lines', () {
      final json = _plain.render(
        httpEntry(method: 'GET', url: '/a', status: 200, response: '{"type":1,"messages":["ok"]}'),
      );
      expect(json.skip(1), ['    resp  type: 1', '          messages: [ok]']);
      final text = _plain.render(httpEntry(method: 'GET', url: '/a', status: 500, response: 'Server error\nTry later'));
      expect(text.skip(1), ['    resp  Server error', '          Try later']);
    });

    test("Dart's map text ({a: 1, b: x}) is split into fields too", () {
      final lines = _plain.render(
        httpEntry(method: 'POST', url: '/a', status: 200, body: '{userId: 1, tags: [a, b], meta: {x: 1}, pin: 9}'),
      );
      expect(lines.skip(1), [
        '    body  userId: 1',
        '          tags: [a, b]',
        '          meta: {x: 1}',
        '          pin: 9',
      ]);
    });

    test('long values are shortened and long bodies stop after 14 lines', () {
      final lines = _plain.render(
        httpEntry(
          method: 'GET',
          url: '/a',
          status: 200,
          response: {for (var i = 0; i < 30; i++) 'field$i': i == 0 ? 'x' * 300 : i},
        ),
      );
      final resp = lines.skip(1).toList();
      expect(resp.first.length, lessThan(130));
      expect(resp.first, endsWith('…'));
      expect(resp, hasLength(15));
      expect(resp.last, '          … 16 more lines');
    });

    test('redact applies to the path, every body line, and tokens anywhere', () {
      const jwt = 'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMDAxIn0.c2lnbmF0dXJl';
      final redactor = Redactor(TidyConfig.defaultRedactKeys);
      final lines = _plain.render(
        httpEntry(
          method: 'GET',
          url: 'http://h:1/api/Auth/SoftOtp?softToken=2A7C2544',
          status: 200,
          response: {'value': jwt, 'walletPin': '1234', 'name': 'Azer'},
          redact: redactor.apply,
        ),
      );
      final all = lines.join('\n');
      expect(lines.first, startsWith('GET    /api/Auth/SoftOtp?softToken=••••••••'));
      expect(all, isNot(contains('2A7C2544')));
      expect(all, isNot(contains('eyJ')));
      expect(all, contains('walletPin: ••••••••'));
      expect(all, contains('name: Azer'));
    });
  });

  test('the path and query are shown decoded, not percent-encoded', () {
    final line = _plain
        .render(httpEntry(method: 'GET', url: 'http://h:1/api/caf%C3%A9?q=%3Credacted%3E&n=a%20b', status: 200))
        .first;
    expect(line, startsWith('GET    /api/café?q=<redacted>&n=a b '));
  });

  test('httpOutcome follows the status class, and a transport error wins', () {
    expect(httpOutcome(status: 201), HttpOutcome.success);
    expect(httpOutcome(status: 302), HttpOutcome.info);
    expect(httpOutcome(status: 422), HttpOutcome.warning);
    expect(httpOutcome(status: 500), HttpOutcome.error);
    expect(httpOutcome(error: 'connection refused'), HttpOutcome.error);
    expect(httpOutcome(), HttpOutcome.success);
  });
}
