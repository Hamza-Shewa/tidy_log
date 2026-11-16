import 'package:flutter_test/flutter_test.dart';
import 'package:tidy_log/src/core.dart';

void main() {
  final redactor = Redactor(TidyConfig.defaultRedactKeys);

  test('masks Dart map, JSON and query values of sensitive keys', () {
    expect(redactor.apply('{userId: 100001, pin: 11112222, authUserType: 0}'), '{userId: 100001, pin: ••••••••, authUserType: 0}');
    expect(redactor.apply('{"password":"hunter2","user":"a"}'), '{"password":"••••••••","user":"a"}');
    expect(redactor.apply('grant=x&token=abc.def&x=1'), 'grant=x&token=••••••••&x=1');
    expect(redactor.apply('Authorization: Bearer abc.def.ghi'), 'Authorization: ••••••••');
  });

  test('leaves words that only contain a key alone', () {
    const text = 'spki_pinning_mismatch: host=example.test:443, SignToken: DEVICE01, pinned: 3';
    expect(redactor.apply(text), text);
  });

  test('does not treat a header separator as a value', () {
    expect(redactor.apply('authorization: | user-agent: | content-type: application/json'), 'authorization: | user-agent: | content-type: application/json');
  });

  test('an empty key list changes nothing', () {
    expect(Redactor(const []).apply('pin: 1234'), 'pin: 1234');
  });
}
