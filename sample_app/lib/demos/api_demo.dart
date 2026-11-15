import 'package:dio/dio.dart';

import '../logging/app_logger.dart';

/// API calls against [MockServer] (and two hosts that cannot answer).
/// Each method returns a short status for the screen. The HTTP line itself
/// comes from the Dio interceptor chosen in `main.dart`.
final class ApiDemo {
  const ApiDemo(this._dio, this._logger);

  final Dio _dio;
  final AppLogger _logger;

  static const _tag = 'Api';

  Future<String> loadAccounts() async {
    final response = await _dio.get<Map<String, Object?>>('/api/accounts');
    final accounts = response.data!['accounts']! as List<Object?>;
    _logger.i('Loaded ${accounts.length} accounts', tag: _tag);
    return 'Loaded ${accounts.length} accounts';
  }

  Future<String> signIn() async {
    final response = await _dio.post<Map<String, Object?>>(
      '/api/Auth/Signin',
      data: {'userId': 7, 'pin': '1234', 'password': 'hunter2'},
    );
    _logger.i('Signed in, token expires in ${response.data!['expiresIn']} s', tag: _tag);
    return 'Signed in';
  }

  /// 401: logged as a warning, the way an app would before refreshing.
  Future<String> loadProfile() => _expectFailure('Profile', () => _dio.get<Object?>('/api/profile'), asWarning: true);

  /// 404 on a route the server does not know.
  Future<String> loadStatements() => _expectFailure('Statements', () => _dio.get<Object?>('/api/statements'), asWarning: true);

  /// 500 with an error body.
  Future<String> sendTransfer() => _expectFailure(
    'Transfer',
    () => _dio.post<Object?>('/api/transfers', data: {'from': 1, 'to': 2, 'amount': '150.000', 'otp': '842913'}),
  );

  /// The server answers after the client's receive timeout.
  Future<String> loadSlowReport() => _expectFailure('Report', () => _dio.get<Object?>('/api/slow'));

  /// 200 with a body that is not valid JSON.
  Future<String> loadBrokenJson() => _expectFailure('Accounts (broken JSON)', () => _dio.get<Object?>('/api/broken-json'));

  /// Nothing listens on port 9, so the connection is refused.
  Future<String> pingRefused() => _expectFailure('Ping', () => _dio.get<Object?>('http://127.0.0.1:9/api/ping'));

  /// `.invalid` never resolves (RFC 2606), so the DNS lookup fails.
  Future<String> pingUnknownHost() => _expectFailure('Ping (DNS)', () => _dio.get<Object?>('http://api.sample.invalid/api/ping'));

  Future<String> _expectFailure(String what, Future<Object?> Function() call, {bool asWarning = false}) async {
    try {
      await call();
      return '$what unexpectedly succeeded';
    } on DioException catch (error, stack) {
      final reason = error.response?.statusCode?.toString() ?? error.type.name;
      if (asWarning) {
        _logger.w('$what failed: $reason', tag: _tag);
      } else {
        _logger.e('$what failed: $reason', tag: _tag, error: error, stackTrace: stack);
      }
      return '$what failed: $reason';
    }
  }
}
