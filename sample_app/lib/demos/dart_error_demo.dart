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

  /// An error thrown after an `await`, with nobody listening.
  Future<String> uncaughtAsync() async {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    throw TimeoutException('Session refresh took too long', const Duration(seconds: 5));
  }
}
