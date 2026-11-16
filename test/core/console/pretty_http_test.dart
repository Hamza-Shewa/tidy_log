import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tidy_log/src/core.dart';

/// Output of a whole run (lines added, then the end of the run), without
/// the "app started" divider.
List<String> run(List<String> lines) {
  final pipeline = ConsolePipeline(TidyConfig(projectPackages: const ['app']));
  const renderer = Renderer(color: false, includeSource: true);
  final entries = [for (final l in lines) ...pipeline.add(l), ...pipeline.finish()];
  return [for (final e in entries) ...renderer.render(e)].where((l) => !l.startsWith('────────')).toList();
}

const _p = 'I/flutter (1): ';

/// The first line of an HTTP entry from a logger without timing: method and
/// path columns, the status, then the host.
String head(String method, String path, String status, String host) =>
    '${method.padRight(7)}${path.padRight(46)}  ${status.padRight(3)}    $host';
final _rule = '╚${'═' * 128}╝';

/// The boxes core_banking's CoreNetworkLogger (a pretty_dio_logger style
/// interceptor) prints, as `flutter run` shows them.
List<String> box(String header, String url, [List<String> rest = const []]) => [
  _p,
  '$_p╔╣ $header',
  '$_p║  $url',
  '$_p$_rule',
  for (final r in rest) '$_p$r',
];

void main() {
  final fixture = File('test/core/fixtures/pretty_dio_session.txt').readAsLinesSync();
  final fakeJwt = fixture.firstWhere((l) => l.contains('bearer ')).split('bearer ').last;

  group('pretty_dio_logger boxes', () {
    test('a request and its response become one HTTP line, without headers or timeouts', () {
      final out = run([
        ...box('Request ║ GET ', 'http://10.0.2.2:4020/api/Auth/SoftOtp?softToken=%3Credacted%3E', [
          '╔ Headers ',
          '╟ content-type: application/json',
          '╟ connectTimeout: 0:01:30.000000',
          _rule,
        ]),
        'D/Other(1): something in between',
        ...box('Response ║ GET ║ Status: 200 OK', 'http://10.0.2.2:4020/api/Auth/SoftOtp?softToken=%3Credacted%3E', [
          '╔ Body',
          '║',
          '║    {',
          '║         content: "111222",',
          '║         type: 1',
          '║    }',
          '║',
          _rule,
        ]),
      ]);
      final http = out.where((l) => l.startsWith('GET ')).toList();
      expect(http, [head('GET', '/api/Auth/SoftOtp?softToken=••••••••', '200', '10.0.2.2:4020')]);
      expect(out, containsAllInOrder(['    resp  content: 111222', '          type: 1']));
      expect(out.join('\n'), isNot(contains('connectTimeout')));
      expect(out.join('\n'), isNot(contains('╔')));
    });

    test('a POST shows its body table on one line, with the PIN masked', () {
      final out = run([
        ...box('Request ║ POST ', 'http://h:1/api/Auth/Signin?', [
          '╔ Body ',
          '╟ userName: 218900000000',
          '╟ pin: 1234',
          _rule,
        ]),
        ...box('Response ║ POST ║ Status: 200 OK', 'http://h:1/api/Auth/Signin?', [
          '╔ Body',
          '║',
          '║    {',
          '║         type: 1',
          '║    }',
          '║',
          _rule,
        ]),
      ]);
      expect(out.first, head('POST', '/api/Auth/Signin', '200', 'h:1'));
      expect(out, containsAllInOrder(['    body  userName: 218900000000', '          pin: ••••••••']));
    });

    test('a 401 error box is matched to its request by URL and keeps the method', () {
      final out = run([
        ...box('Request ║ POST ', 'http://h:1/api/Transfer/Execute?', ['╔ Body ', '╟ amount: 150.5', _rule]),
        ...box('DioError ║ Status: 401 Unauthorized', 'http://h:1/api/Transfer/Execute?', [
          '╔ DioExceptionType.badResponse',
          '║    {',
          '║         messages: ["Session expired"]',
          '║    }',
          _rule,
          '',
        ]),
      ]);
      expect(out, [
        head('POST', '/api/Transfer/Execute', '401', 'h:1'),
        '    body  amount: 150.5',
        '    resp  messages: ["Session expired"]',
      ]);
    });

    test('a transport error is matched to the only open request', () {
      final out = run([
        ...box('Request ║ GET ', 'http://h:1/api/Inbox/List?'),
        ...box(
          'DioError ║ DioExceptionType.connectionError',
          'The connection errored: Connection refused This indicates an error which most likely cannot be solved by the library.',
        ),
      ]);
      expect(out, [head('GET', '/api/Inbox/List', 'ERR', 'h:1'), '    ✕ connection error: Connection refused']);
    });

    test('two calls to the same URL are answered in the order they were sent', () {
      final out = run([
        ...box('Request ║ POST ', 'http://h:1/api/pay?', ['╔ Body ', '╟ amount: 1', _rule]),
        ...box('Request ║ POST ', 'http://h:1/api/pay?', ['╔ Body ', '╟ amount: 2', _rule]),
        ...box('Response ║ POST ║ Status: 200 OK', 'http://h:1/api/pay?'),
        ...box('DioError ║ Status: 500 Internal Server Error', 'http://h:1/api/pay?'),
      ]);
      expect(out, [
        head('POST', '/api/pay', '200', 'h:1'),
        '    body  amount: 1',
        head('POST', '/api/pay', '500', 'h:1'),
        '    body  amount: 2',
      ]);
    });

    test('a transport error with several open requests does not guess which one failed', () {
      final out = run([
        ...box('Request ║ GET ', 'http://h:1/a?'),
        ...box('Request ║ GET ', 'http://h:1/b?'),
        ...box('DioError ║ DioExceptionType.receiveTimeout', 'null'),
      ]);
      expect(out, [
        'ERR HTTP receive timeout',
        head('GET', '/a', '', 'h:1'),
        '    · no response logged',
        head('GET', '/b', '', 'h:1'),
        '    · no response logged',
      ]);
    });

    test('a request still open at the end of the run is reported, but never while it is open', () {
      final pipeline = ConsolePipeline(TidyConfig());
      const renderer = Renderer(color: false);
      final whileOpen = [
        for (final l in box('Request ║ GET ', 'http://h:1/api/Cards/List?')) ...pipeline.add(l),
        ...pipeline.flush(),
      ];
      expect(
        [for (final e in whileOpen) ...renderer.render(e)].where((l) => !l.startsWith('────────')),
        isEmpty,
        reason: 'an idle flush must not print a request that may still get its response',
      );
      final atEnd = [for (final e in pipeline.finish()) ...renderer.render(e)];
      expect(atEnd, [head('GET', '/api/Cards/List', '', 'h:1'), '    · no response logged']);
    });

    test('a route line followed by the blank line before a box is still a NAV line', () {
      final out = run(['${_p}from /login Pushed route: /accounts', _p, ...box('Request ║ GET ', 'http://h:1/a?')]);
      expect(out.first, 'NAV /login → /accounts');
    });

    test('a long token is masked before the body is shortened, so what follows it survives', () {
      final out = run([
        ...box('Request ║ GET ', 'http://h:1/a?'),
        ...box('Response ║ GET ║ Status: 200 OK', 'http://h:1/a?', [
          '╔ Body',
          '║    {',
          '║         access: "$fakeJwt",',
          '║         type: 1',
          '║    }',
          _rule,
        ]),
      ]);
      expect(out, containsAllInOrder(['    resp  access: ••••••••', '          type: 1']));
    });

    test('list items keep a "- " marker so several items stay apart', () {
      final out = run([
        ...box('Request ║ GET ', 'http://h:1/accounts?'),
        ...box('Response ║ GET ║ Status: 200 OK', 'http://h:1/accounts?', [
          '╔ Body',
          '║',
          '║    {',
          '║         content: [',
          '║            {',
          '║                 accId: 1,',
          '║                 nickName: "Main"',
          '║            },',
          '║            {',
          '║                 accId: 2,',
          '║                 nickName: "Savings"',
          '║            }',
          '║         ],',
          '║         type: 1',
          '║    }',
          '║',
          _rule,
        ]),
      ]);
      expect(out.skip(1), [
        '    resp  content:',
        '            - accId: 1',
        '              nickName: Main',
        '            - accId: 2',
        '              nickName: Savings',
        '          type: 1',
      ]);
    });

    test('the blank lines the logger prints between boxes do not show up', () {
      final out = run([_p, _p, '${_p}ar_LY']);
      expect(out, ['    ar_LY']);
    });
  });

  group('tokens', () {
    test('a JWT the logger wrapped over several lines is masked entirely', () {
      final out = run(fixture).join('\n');
      expect(out, isNot(contains('eyJ')));
      for (final piece in fakeJwt.split('.')) {
        expect(out, isNot(contains(piece.substring(piece.length - 12))), reason: 'no tail of any JWT part may leak');
      }
    });

    test('a JWT printed by app code is masked, ordinary words are not', () {
      final out = run(['${_p}session refreshed, bearer $fakeJwt', '${_p}the eyes have it']);
      expect(out, contains('    session refreshed, bearer ••••••••'));
      expect(out, contains('    the eyes have it'));
    });
  });

  test('the whole fixture folds to the reviewed output', () {
    final expected = File('test/core/fixtures/pretty_dio_session.expected.txt').readAsLinesSync();
    final pipeline = ConsolePipeline(TidyConfig(projectPackages: const ['app'], color: false));
    const renderer = Renderer(color: false);
    final actual = [
      for (final e in [for (final l in fixture) ...pipeline.add(l), ...pipeline.finish()]) ...renderer.render(e),
    ];
    expect(actual, expected);
    expect(actual.length, lessThan(fixture.length ~/ 4), reason: 'these boxes are mostly noise');
  });
}
