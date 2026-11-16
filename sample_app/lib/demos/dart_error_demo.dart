import 'dart:async';
import 'dart:convert';

import '../logging/app_logger.dart';

/// Plain Dart mistakes. Most of these throw on purpose and are left
/// uncaught, so the console shows what Flutter does with them.
final class DartErrorDemo {
  DartErrorDemo(this._logger);

  final AppLogger _logger;

  /// Never set: stands in for state that was not loaded yet.
  String? _selectedAccount;

  /// `Null check operator used on a null value`.
  int nullCheck() => _selectedAccount!.length;

  /// `type 'String' is not a subtype of type 'num' in type cast`.
  num badCast() {
    final decoded = jsonDecode('{"amount": "12.5"}') as Map<String, Object?>;
    return decoded['amount']! as num;
  }

  /// `RangeError (length): Invalid value: Not in inclusive range 0..1: 5`.
  String rangeError() => const ['Current', 'Savings'][5];

  /// `Bad state: No element`.
  String stateError() => const <String>[].first;

  /// A failed `assert` (debug builds only).
  void failedAssert({int amount = -5}) {
    assert(amount > 0, 'Transfer amount must be positive, got $amount');
  }

  /// A `FormatException` that the app catches and logs with its stack.
  String caughtFormatError() {
    try {
      return '${_parseAmount('12,5')}';
    } on FormatException catch (error, stack) {
      _logger.e('Could not parse the amount', tag: 'Transfer', error: error, stackTrace: stack);
      return 'Logged a caught FormatException';
    }
  }

  int _parseAmount(String text) => int.parse(text);

  /// Never assigned: stands in for a field read before `init()` ran.
  late String _sessionToken;

  /// `LateInitializationError: Field '_sessionToken' has not been initialized.`
  int lateInit() => _sessionToken.length;

  /// A stream error with no `onError`: reported as an uncaught error.
  String uncaughtStream() {
    Stream<int>.error(StateError('Socket closed by the server')).listen((_) {});
    return 'Listened to a failing stream';
  }

  /// Throws at the bottom of a 200-frame recursion, to see how each console
  /// copes with a long stack of the app's own frames.
  int deepRecursion([int depth = 200]) => depth == 0 ? throw StateError('Reached the bottom of a 200-frame recursion') : deepRecursion(depth - 1) + 1;

  /// An error thrown after an `await`, with nobody listening.
  Future<String> uncaughtAsync() async {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    throw TimeoutException('Session refresh took too long', const Duration(seconds: 5));
  }
}
