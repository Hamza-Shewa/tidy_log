import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:tidy_log/tidy_log.dart';

void main() {
  TidyLog.configure(projectPackages: ['tidy_log_example']);
  // Before any crash reporter, so it calls the tidy formatter.
  TidyLog.installErrorHooks();
  runApp(const ExampleApp());
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key, this.dio});

  final Dio? dio;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'tidy_log example',
      theme: ThemeData(colorSchemeSeed: Colors.teal),
      home: DemoPage(dio: dio),
    );
  }
}

/// Buttons that produce each kind of log line, to see tidy_log in the
/// Debug Console.
class DemoPage extends StatefulWidget {
  const DemoPage({super.key, this.dio});

  final Dio? dio;

  @override
  State<DemoPage> createState() => _DemoPageState();
}

class _DemoPageState extends State<DemoPage> {
  late final Dio _dio = widget.dio ??
      (Dio(BaseOptions(connectTimeout: const Duration(seconds: 2)))..interceptors.add(TidyDioInterceptor()));
  String _status = 'Tap a button and watch the Debug Console.';

  void _logLevels() {
    TidyLog.d('Loaded 12 accounts', tag: 'AccountsRepo');
    TidyLog.i('Signed in {userId: 7, pin: 1234}', tag: 'Auth');
    TidyLog.w('Token expires in 30 s', tag: 'Auth');
    _setStatus('Logged one line per level.');
  }

  void _logCaught() {
    try {
      _parseAmount('12,5');
    } catch (error, stack) {
      TidyLog.e('Could not parse the amount', tag: 'Transfer', error: error, stackTrace: stack);
    }
    _setStatus('Logged a caught error with its location.');
  }

  int _parseAmount(String text) => int.parse(text);

  void _throwInHandler() {
    _setStatus('Threw inside a tap handler.');
    throw StateError('No account selected');
  }

  void _throwAsync() {
    _setStatus('Threw an uncaught async error.');
    unawaited(Future<void>.delayed(Duration.zero, () => throw TimeoutException('Session refresh took too long')));
  }

  Future<void> _callApi() async {
    _setStatus('Calling an API that refuses the connection…');
    try {
      await _dio.post<Object?>('http://127.0.0.1:9/api/Auth/Signin', data: {'userId': 7, 'pin': 1234});
    } on DioException {
      _setStatus('The API call failed (see the console).');
    }
  }

  void _setStatus(String text) {
    if (mounted) setState(() => _status = text);
  }

  @override
  Widget build(BuildContext context) {
    final actions = <(String, IconData, VoidCallback)>[
      ('Log each level', Icons.list_alt, _logLevels),
      ('Log a caught error', Icons.error_outline, _logCaught),
      ('Throw in a tap handler', Icons.touch_app, _throwInHandler),
      ('Throw an async error', Icons.timer_off, _throwAsync),
      ('Call a failing API', Icons.cloud_off, _callApi),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('tidy_log example')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(_status, key: const Key('status'), style: Theme.of(context).textTheme.bodyLarge),
          const SizedBox(height: 16),
          for (final (label, icon, onTap) in actions)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: FilledButton.tonalIcon(
                onPressed: onTap,
                icon: Icon(icon),
                label: Text(label),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              ),
            ),
        ],
      ),
    );
  }
}
