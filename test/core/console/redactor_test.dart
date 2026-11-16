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
}
