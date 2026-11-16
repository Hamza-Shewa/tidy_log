import 'package:flutter_test/flutter_test.dart';
import 'package:tidy_log/src/core.dart';

const _styled = Renderer(includeSource: false);
const _plain = Renderer(color: false);

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
    test('turns a 200 red and shows the verdict after a ✕', () {
      final entry = httpEntry(
        method: 'post',
        url: 'http://10.0.2.2:4013/api/Auth/OpenSession',
        status: 200,
        outcome: HttpOutcome.error,
        verdict: 'unvalid api sign',
        rule: 'type = 2 → error',
        response: '{type: 2}',
      );
      expect(_statusCode(entry, '200'), '1;31');
      expect(_plain.render(entry), [
        'POST /api/Auth/OpenSession  10.0.2.2:4013  200 ✕ unvalid api sign',
        '    rule  type = 2 → error',
        '    resp  {type: 2}',
      ]);
    });

    test('a warning is yellow with "!"; success with a verdict is dim', () {
      final warning = httpEntry(method: 'GET', url: '/s', status: 200, outcome: HttpOutcome.warning, verdict: 'expires soon');
      expect(_statusCode(warning, '200'), '33');
      expect(_plain.render(warning).single, 'GET /s  200 ! expires soon');

      final ok = httpEntry(method: 'GET', url: '/s', status: 400, outcome: HttpOutcome.success, verdict: 'validated');
      expect(_statusCode(ok, '400'), '1;32', reason: 'the rule wins over the status class');
      expect(_plain.render(ok).single, 'GET /s  400 · validated');
    });

    test('a long or multi-line verdict is shortened to one line', () {
      final entry = httpEntry(method: 'GET', url: '/s', status: 200, outcome: HttpOutcome.error, verdict: 'line one\n${'x' * 200}');
      final head = _plain.render(entry).single;
      expect(head, startsWith('GET /s  200 ✕ line one x'));
      expect(head, endsWith('…'));
      expect(head.length, lessThan(110));
    });
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
