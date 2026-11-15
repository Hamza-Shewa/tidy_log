import 'package:flutter/foundation.dart';

import '../logging/app_logger.dart';

/// Ordinary log lines: each level, secrets, repeats and a raw print.
final class LogDemo {
  const LogDemo(this._logger, {this._printer});

  final AppLogger _logger;
  final DebugPrintCallback? _printer;

  /// Defaults to [debugPrint]; tests pass their own.
  DebugPrintCallback get printer => _printer ?? debugPrint;

  String levels() {
    _logger.d('Loaded 12 accounts', tag: 'AccountsRepo');
    _logger.i('Signed in {userId: 7, pin: 1234, password: hunter2}', tag: 'Auth');
    _logger.w('Token expires in 30 s', tag: 'Auth');
    _logger.e('Biometric prompt dismissed by the user', tag: 'Auth');
    return 'Logged one line per level';
  }

  /// 25 identical lines, then 8 lines that differ only by a number.
  String repeats() {
    for (var i = 0; i < 25; i++) {
      _logger.d('Polling balance', tag: 'BalancePoller');
    }
    for (var i = 1; i <= 8; i++) {
      _logger.d('Synced account $i of 8', tag: 'Sync');
    }
    return 'Logged 25 repeats and 8 near-duplicates';
  }

  /// `debugPrint` straight from app code, the way older code logs.
  String rawPrints() {
    printer('fetchAccounts() start');
    printer('response: {"accounts":[{"id":1,"iban":"LY83002048000020100120361","balance":"1250.500"}],"token":"eyJhbGciOiJIUzI1NiJ9.raw"}');
    printer('fetchAccounts() done in 182 ms');
    return 'Printed three raw lines';
  }
}
