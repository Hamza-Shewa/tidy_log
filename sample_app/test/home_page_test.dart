import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tidy_log_sample/main.dart';
import 'package:tidy_log_sample/pages/home_page.dart';
import 'package:tidy_log_sample/scenarios/catalog.dart';
import 'package:tidy_log_sample/scenarios/scenario.dart';

import 'helpers.dart';

void main() {
  late RecordingLogger logger;

  setUp(() => logger = RecordingLogger());

  Future<void> pumpApp(WidgetTester tester, {bool tidy = true}) =>
      tester.pumpWidget(SampleApp(demos: demosWith(logger, printed: []), tidy: tidy));

  Future<void> tapScenario(WidgetTester tester, String title) async {
    await tester.ensureVisible(find.text(title));
    await tester.tap(find.text(title));
    await tester.pump();
  }

  testWidgets('lists every group and scenario with its expected output', (tester) async {
    await pumpApp(tester);

    for (final group in ScenarioGroup.values) {
      expect(find.text(group.label), findsOneWidget);
    }
    for (final scenario in scenarios) {
      expect(find.text(scenario.title), findsOneWidget, reason: scenario.id);
      expect(find.text(scenario.expected), findsOneWidget, reason: scenario.id);
    }
    expect(find.text('Tap a scenario and watch the console.'), findsOneWidget);
    expect(find.text('Run all'), findsOneWidget);
  });

  testWidgets('scenario ids are unique, so "Run all" markers are unambiguous', (tester) async {
    expect(scenarios.map((s) => s.id).toSet(), hasLength(scenarios.length));
  });

  testWidgets('the mode label says whether tidy_log is on', (tester) async {
    await pumpApp(tester, tidy: false);
    expect(find.text('tidy_log: off (default Flutter output)'), findsOneWidget);

    await pumpApp(tester);
    expect(find.text('tidy_log: on'), findsOneWidget);
  });

  testWidgets('"Log each level" logs one line per level and shows its status', (tester) async {
    await pumpApp(tester);
    await tapScenario(tester, 'Log each level');

    expect(logger.records.map((r) => r.level), ['d', 'i', 'w', 'e']);
    expect(logger.records[1].message, 'Signed in {userId: 7, pin: 1234, password: hunter2}');
    expect(find.text('Logged one line per level'), findsOneWidget);
  });

  testWidgets('a throwing tap handler reaches Flutter as an uncaught error', (tester) async {
    await pumpApp(tester);
    await tapScenario(tester, 'Null check in a tap handler');

    final error = tester.takeException();
    expect(error, isA<TypeError>());
    expect('$error', contains('Null check operator used on a null value'));
    expect(find.text('Null check in a tap handler: see the console.'), findsOneWidget);
    expect(logger.records, isEmpty);
  });

  testWidgets('an unknown named route throws from the navigator', (tester) async {
    await pumpApp(tester);
    await tapScenario(tester, 'Push an unknown named route');

    expect('${tester.takeException()}', contains('Could not find a generator for route RouteSettings("/transfers/42"'));
  });

  testWidgets('autorun taps every scenario once, in order, through pointer events', (tester) async {
    final ran = <String>[];
    Scenario recorder(String id) => Scenario(
      id: id,
      group: ScenarioGroup.logs,
      title: 'Scenario $id',
      expected: 'records $id',
      run: (_, _) {
        ran.add(id);
        return 'ran $id';
      },
      settle: const Duration(milliseconds: 10),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(scenarios: [recorder('a'), recorder('b'), recorder('c')], demos: demosWith(logger), modeLabel: 'test', autorun: true),
      ),
    );
    for (var i = 0; i < 20 && ran.length < 3; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();

    expect(ran, ['a', 'b', 'c']);
    expect(find.text('ran c'), findsOneWidget);
    expect(find.text('Run all'), findsOneWidget, reason: 'the button is enabled again when the run ends');
  });

  testWidgets('a page scenario opens its page and the back button returns', (tester) async {
    await pumpApp(tester);
    await tapScenario(tester, 'Row overflow');
    await tester.pumpAndSettle();
    tester.takeException(); // the overflow itself, covered in broken_pages_test

    expect(find.widgetWithText(AppBar, 'Overflow'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('tidy_log sample'), findsOneWidget);
  });
}
