import 'package:flutter_test/flutter_test.dart';
import 'package:tidy_log/src/core.dart';

void main() {
  group('FieldRule', () {
    final type = FieldRule('type', {1: HttpOutcome.success}, otherwise: HttpOutcome.error, message: 'messages');

    test('a listed value gives its outcome, matched leniently', () {
      expect(type.decide({'type': 1})?.outcome, HttpOutcome.success);
      expect(type.decide({'type': '1'})?.outcome, HttpOutcome.success);
      final caseless = FieldRule('status', {'OK': HttpOutcome.success});
      expect(caseless.decide({'status': 'ok'})?.outcome, HttpOutcome.success);
    });

    test('an unlisted value gets otherwise, with the message and the rule that decided', () {
      final verdict = type.decide({
        'type': 3,
        'messages': ['حدثت مشكلة في الخادم'],
      })!;
      expect(verdict.outcome, HttpOutcome.error);
      expect(verdict.message, 'حدثت مشكلة في الخادم');
      expect(verdict.rule, 'type = 3 → error');
    });

    test('no verdict when the field is missing, or unlisted without otherwise', () {
      expect(type.decide({'content': 1}), isNull);
      expect(type.decide('not json'), isNull);
      expect(FieldRule('type', {1: HttpOutcome.success}).decide({'type': 3}), isNull);
    });

    test('a dotted path reaches into maps and lists', () {
      final rule = FieldRule('errors.0.code', {'E1': HttpOutcome.warning});
      expect(
        rule.decide({
          'errors': [
            {'code': 'E1'},
          ],
        })?.outcome,
        HttpOutcome.warning,
      );
    });
  });

  group('bodyFromLines', () {
    test('reads the one-field-per-line body back into maps and lists', () {
      final body = bodyFromLines([
        'type: 3',
        'messages: ["Session expired", "Sign in again"]',
        'content:',
        '  balance: 10',
        'accounts:',
        '  - accId: 1',
        '    nickName: Main',
      ]);
      expect(lookup(body, 'type'), (true, 3));
      expect(textAt(body, 'messages'), 'Session expired');
      expect(lookup(body, 'content.balance'), (true, 10));
      expect(lookup(body, 'accounts.0.nickName'), (true, 'Main'));
    });

    test('lines that are not valid YAML still give their top-level fields', () {
      final body = bodyFromLines(['type: 2', 'note: a: b: [unclosed', '  "x"', '  "y"']);
      expect(lookup(body, 'type'), (true, 2));
    });

    test('an empty body is null', () {
      expect(bodyFromLines(const []), isNull);
    });
  });
}
