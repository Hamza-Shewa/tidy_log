import 'package:flutter_test/flutter_test.dart';
import 'package:tidy_log/tidy_log.dart';
import 'package:tidy_log_example/main.dart';

void main() {
  late List<String> printed;

  setUp(() {
    printed = [];
    TidyLog.reset();
    TidyLog.configure(enabled: true, color: false, printer: printed.add, projectPackages: ['tidy_log_example']);
  });
  tearDown(TidyLog.reset);

  testWidgets('shows every demo action and the starting hint', (tester) async {
    await tester.pumpWidget(const ExampleApp());
    expect(find.text('Tap a button and watch the Debug Console.'), findsOneWidget);
    for (final label in [
      'Log each level',
      'Log a caught error',
      'Throw in a tap handler',
      'Throw an async error',
      'Call a failing API',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
  });

  testWidgets('"Log each level" logs three levels with the PIN masked', (tester) async {
    await tester.pumpWidget(const ExampleApp());
    await tester.tap(find.text('Log each level'));
    await tester.pump();

    expect(printed.map((l) => l.split('  ').first), [
      'DBG Loaded 12 accounts',
      'INF Signed in {userId: 7, pin: ••••••••}',
      'WRN Token expires in 30 s',
    ]);
    expect(find.text('Logged one line per level.'), findsOneWidget);
  });

  testWidgets('"Log a caught error" points at the line in this app', (tester) async {
    await tester.pumpWidget(const ExampleApp());
    await tester.tap(find.text('Log a caught error'));
    await tester.pump();

    expect(printed.first, startsWith('ERR Could not parse the amount'));
    expect(printed, contains(matches(RegExp(r'^    at lib/main\.dart:\d+:\d+  _DemoPageState\._parseAmount$'))));
  });
}
