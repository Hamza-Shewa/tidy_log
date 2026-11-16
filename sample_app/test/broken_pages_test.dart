import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tidy_log_sample/pages/broken_pages.dart';

/// Each broken page must trigger exactly the error it promises, otherwise
/// the console comparison would be comparing the wrong thing.
void main() {
  Future<List<FlutterErrorDetails>> pumpAndCollect(WidgetTester tester, Widget page) async {
    final errors = <FlutterErrorDetails>[];
    final original = FlutterError.onError;
    FlutterError.onError = errors.add;
    try {
      await tester.pumpWidget(MaterialApp(home: page));
      await tester.pump();
    } finally {
      FlutterError.onError = original;
    }
    return errors;
  }

  final cases = <(String, Widget, String, String)>[
    ('null in build', const NullInBuildPage(), 'Null check operator used on a null value', 'widgets library'),
    ('overflow', const OverflowPage(), 'A RenderFlex overflowed by', 'rendering library'),
    ('unbounded height', const UnboundedHeightPage(), 'Vertical viewport was given unbounded height.', 'rendering library'),
    ('unbounded width', const UnboundedWidthFieldPage(), 'An InputDecorator, which is typically created by a TextField, cannot have an unbounded width.', 'rendering library'),
    ('parent data', const WrongParentDataPage(), 'Incorrect use of ParentDataWidget.', 'widgets library'),
  ];

  for (final (name, page, message, library) in cases) {
    testWidgets('$name page reports "$message"', (tester) async {
      final errors = await pumpAndCollect(tester, page);

      expect(errors, isNotEmpty);
      expect(errors.first.exceptionAsString(), contains(message));
      expect(errors.first.library, library);
    });
  }

  testWidgets('the app bar of a broken page still renders', (tester) async {
    await pumpAndCollect(tester, const NullInBuildPage());
    expect(find.widgetWithText(AppBar, 'Null in build'), findsOneWidget);
    expect(find.byType(ErrorWidget), findsOneWidget);
  });

  testWidgets('the repeating page throws the same build error on every frame', (tester) async {
    final errors = <FlutterErrorDetails>[];
    final original = FlutterError.onError;
    FlutterError.onError = errors.add;
    try {
      await tester.pumpWidget(const MaterialApp(home: RepeatingErrorPage()));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
    } finally {
      FlutterError.onError = original;
    }
    expect(errors.length, greaterThanOrEqualTo(5));
    expect(errors.map((e) => e.exceptionAsString()).toSet(), {'Bad state: Price feed not loaded'});
  });

  testWidgets('the late setState page calls setState after it was closed', (tester) async {
    // The page's timer is created in initState, so building it inside this
    // zone sends the timer's error here instead of failing the test.
    final errors = <Object>[];
    await runZonedGuarded(
      () => tester.pumpWidget(const MaterialApp(home: LateSetStatePage(delay: Duration(milliseconds: 100)))),
      (error, _) => errors.add(error),
    );
    expect(find.text('Loading…'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 200));

    expect(errors.map((e) => '$e'), [contains('setState() called after dispose()')]);
  });
}
