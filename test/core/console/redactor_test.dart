import 'package:flutter_test/flutter_test.dart';
import 'package:tidy_log/src/core.dart';

void main() {
  final redactor = Redactor(TidyConfig.defaultRedactKeys);

  test('masks Dart map, JSON and query values of sensitive keys', () {
    expect(
      redactor.apply('{userId: 100001, pin: 11112222, authUserType: 0}'),
      '{userId: 100001, pin: ••••••••, authUserType: 0}',
    );
    expect(redactor.apply('{"password":"hunter2","user":"a"}'), '{"password":"••••••••","user":"a"}');
    expect(redactor.apply('grant=x&token=abc.def&x=1'), 'grant=x&token=••••••••&x=1');
    expect(redactor.apply('Authorization: Bearer abc.def.ghi'), 'Authorization: ••••••••');
  });

  test('masks compound keys that end in a secret word (softToken, newPassword)', () {
    expect(
      redactor.apply('/api/Auth/SoftOtp?softToken=2A7C254415F70FFE&lang=ar'),
      '/api/Auth/SoftOtp?softToken=••••••••&lang=ar',
    );
    expect(redactor.apply('refreshToken: abc, accessToken: def'), 'refreshToken: ••••••••, accessToken: ••••••••');
    expect(
      redactor.apply('{"newPassword":"x","clientSecret":"y"}'),
      '{"newPassword":"••••••••","clientSecret":"••••••••"}',
    );
    expect(redactor.apply('SignToken: DEVICE01'), 'SignToken: ••••••••');
  });

  test('masks keys that end in a short secret word (pin, otp, cvv)', () {
    expect(
      redactor.apply('walletPin: 1234, smsOtp: 987654, cardCvv: 123'),
      'walletPin: ••••••••, smsOtp: ••••••••, cardCvv: ••••••••',
    );
  });

  test('leaves keys that only contain a short secret word alone', () {
    const text =
        'spki_pinning_mismatch: host=example.test:443, pinned: 3, otpChannelReceiver: 0, pinCount: 2, tokenExpiry: 3600';
    expect(redactor.apply(text), text);
  });

  test('a key inside another value is still found', () {
    expect(redactor.apply('Bad state: token: abc123'), 'Bad state: token: ••••••••');
    expect(redactor.apply('error: pin=1234 rejected'), 'error: pin=•••••••• rejected');
  });

  test('an empty value stays visible as empty', () {
    expect(redactor.apply('refreshToken: , systemIdentity: 9106'), 'refreshToken: , systemIdentity: 9106');
  });

  test('does not treat a header separator as a value', () {
    expect(
      redactor.apply('authorization: | user-agent: | content-type: application/json'),
      'authorization: | user-agent: | content-type: application/json',
    );
  });

  test('an empty key list changes nothing', () {
    expect(Redactor(const []).apply('pin: 1234'), 'pin: 1234');
  });

  group('masks the whole value, whatever its shape', () {
    const e = '\x1B';
    for (final (name, input, expected) in [
      // ANSI colour codes are skipped while matching and kept out of the mask.
      ('colour code right before the key', '$e[33mtoken=abc123$e[0m', '$e[33mtoken=••••••••$e[0m'),
      ('colour code, a space, then the key', '$e[33m token=abc123$e[0m', '$e[33m token=••••••••$e[0m'),
      ('logger-style coloured line', '$e[38;5;12mpassword: hunter2$e[0m', '$e[38;5;12mpassword: ••••••••$e[0m'),
      ('colour code inside the value', 'pin: 12$e[1m34$e[0m', 'pin: ••••••••$e[1m$e[0m'),
      // Quoted values end at their closing quote.
      ('comma in a quoted value', '{"password":"p@ss,word!"}', '{"password":"••••••••"}'),
      ('ampersand in a quoted value', '{"password":"Tom&Jerry1"}', '{"password":"••••••••"}'),
      ('pipe and brace in a quoted value', '{"secret":"a|b}c"}', '{"secret":"••••••••"}'),
      ('escaped quote in a quoted value', r'{"password":"a\"b,c"}', '{"password":"••••••••"}'),
      ('quoted multi-word value', '{"password": "my secret pass"}', '{"password": "••••••••"}'),
      ('single-quoted multi-word value', "password: 'correct horse battery'", "password: '••••••••'"),
      // Unquoted values after `:` end at the end of the field.
      ('unquoted multi-word value', 'password: correct horse battery', 'password: ••••••••'),
      ('apostrophe in an unquoted value', "{password: it's-me, user: a}", '{password: ••••••••, user: a}'),
      ('ampersand in an unquoted value', 'password: Tom&Jerry1', 'password: ••••••••'),
      ('pipe inside an unquoted value', 'password: a|b}c', 'password: ••••••••}c'),
      ('list value', 'pin: [1, 2, 3, 4]', 'pin: ••••••••'),
      ('list of tokens', 'token: [abc, def], next: 1', 'token: ••••••••, next: 1'),
      ('map value', 'secret: {a: 1, b: 2}, next: 1', 'secret: ••••••••, next: 1'),
      ('bearer inside a list', '{authorization: [Bearer abc123]}', '{authorization: ••••••••}'),
      // Values after `=` end at a query, cookie or word boundary.
      ('query pairs', 'a=1&password=Tom&b=2', 'a=1&password=••••••••&b=2'),
      ('cookie pairs', 'cookie: theme=dark; sessionid=abc', 'cookie: ••••••••'),
      ('set-cookie value', 'sessionId=abc123; Path=/; HttpOnly', 'sessionId=••••••••; Path=/; HttpOnly'),
      ('list after =', 'token=[a, b]&x=1', 'token=••••••••&x=1'),
      // Key shapes.
      ('escaped JSON inside a string', r'body: "{\"password\":\"hunter2\"}"', r'body: "{\"password\":\"••••••••\"}"'),
      ('escaped JSON, escaped quote inside', r'{\"pin\":\"1\\\"2\",\"a\":1}', r'{\"pin\":\"••••••••\",\"a\":1}'),
      ('bracketed form key', 'user[password]=hunter2&user[name]=a', 'user[password]=••••••••&user[name]=a'),
      ('bracketed key with an index', 'pin[0]=1&pin[1]=2', 'pin[0]=••••••••&pin[1]=••••••••'),
      ('dotted key', 'user.password=hunter2', 'user.password=••••••••'),
      // Authorization schemes: the whole credential.
      ('Bearer', 'Authorization: Bearer abc.def.ghi', 'Authorization: ••••••••'),
      ('Basic after =', 'authorization=Basic dTpw&x=1', 'authorization=••••••••&x=1'),
      ('Token scheme', '"Authorization": "Token abc def"', '"Authorization": "••••••••"'),
      (
        'Digest with its parameters',
        'Authorization: Digest username="u", realm="r, x", response="deadbeef"',
        'Authorization: ••••••••',
      ),
      (
        'Digest then a column',
        'authorization: Digest a="1", b=2 | accept: */*',
        'authorization: •••••••• | accept: */*',
      ),
      // New default keys.
      ('api key header', 'x-api-key: sk_live_123', 'x-api-key: ••••••••'),
      ('apiKey', '{"apiKey":"sk_live_123"}', '{"apiKey":"••••••••"}'),
      ('pin code and otp code', 'pinCode=1234&otp_code=999', 'pinCode=••••••••&otp_code=••••••••'),
      ('cvv2 and cvc', 'cvv2: 123, cvc: 456', 'cvv2: ••••••••, cvc: ••••••••'),
      ('set-cookie header', 'set-cookie: a=1; Path=/', 'set-cookie: ••••••••'),
      ('JSESSIONID', 'JSESSIONID=ABC123', 'JSESSIONID=••••••••'),
      (
        'private and access keys',
        'privateKey: k1, secretAccessKey: k2',
        'privateKey: ••••••••, secretAccessKey: ••••••••',
      ),
      // Left alone.
      ('pinCount', 'pinCount: 3', 'pinCount: 3'),
      ('tokenExpiry', 'tokenExpiry: 10', 'tokenExpiry: 10'),
      ('a key that is not sensitive does not hide the next one', 'state: token: abc', 'state: token: ••••••••'),
      ('cookie consent', 'cookieConsent: true', 'cookieConsent: true'),
      ('empty quoted value', '{"password":""}', '{"password":""}'),
    ]) {
      test(name, () => expect(redactor.apply(input), expected));
    }
  });

  test('a mask never swallows the colour reset', () {
    final out = redactor.apply('\x1B[33m token=abc123\x1B[0m');
    expect(out, endsWith('\x1B[0m'));
    expect(out, isNot(contains('abc123')));
  });
}
