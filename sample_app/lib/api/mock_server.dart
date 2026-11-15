import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// A tiny HTTP server on the device's loopback interface, so the API
/// scenarios need no network and always answer the same way.
///
/// | Route                   | Answer                                   |
/// |-------------------------|------------------------------------------|
/// | `GET /api/accounts`     | 200, three accounts                      |
/// | `POST /api/Auth/Signin` | 200, a token                             |
/// | `GET /api/profile`      | 401, token expired                       |
/// | `POST /api/transfers`   | 500, service unavailable                 |
/// | `GET /api/slow`         | 200 after [slowDelay] (longer than the client's receive timeout) |
/// | `GET /api/broken-json`  | 200 with a truncated JSON body           |
/// | anything else           | 404                                      |
final class MockServer {
  MockServer._(this._server, this.slowDelay);

  final HttpServer _server;
  final Duration slowDelay;

  static Future<MockServer> start({Duration slowDelay = const Duration(seconds: 3)}) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final mock = MockServer._(server, slowDelay);
    server.listen((request) => unawaited(mock._handle(request)));
    return mock;
  }

  Uri get baseUri => Uri.parse('http://${_server.address.host}:${_server.port}');

  Future<void> close() => _server.close(force: true);

  Future<void> _handle(HttpRequest request) async {
    final route = '${request.method} ${request.uri.path}';
    final body = await utf8.decoder.bind(request).join();
    switch (route) {
      case 'GET /api/accounts':
        await _json(request, 200, {
          'accounts': [
            {'id': 1, 'name': 'Current', 'balance': '1250.500'},
            {'id': 2, 'name': 'Savings', 'balance': '9800.000'},
            {'id': 3, 'name': 'Card', 'balance': '-42.125'},
          ],
        });
      case 'POST /api/Auth/Signin':
        final pin = (jsonDecode(body.isEmpty ? '{}' : body) as Map<String, Object?>)['pin'];
        await _json(request, 200, {'token': 'eyJhbGciOiJIUzI1NiJ9.sample.$pin', 'expiresIn': 30});
      case 'GET /api/profile':
        await _json(request, 401, {'error': 'token expired'});
      case 'POST /api/transfers':
        await _json(request, 500, {
          'type': 2,
          'messages': ['Transfer service unavailable'],
        });
      case 'GET /api/slow':
        await Future<void>.delayed(slowDelay);
        await _json(request, 200, {'ok': true});
      case 'GET /api/broken-json':
        request.response.headers.contentType = ContentType.json;
        request.response.write('{"accounts": [1, 2,');
        await request.response.close();
      default:
        await _json(request, 404, {'error': 'no route for $route'});
    }
  }

  static Future<void> _json(HttpRequest request, int status, Object body) async {
    request.response
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(body));
    await request.response.close();
  }
}
