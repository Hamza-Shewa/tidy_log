import 'dart:io';

// flutter/material is deprecated from Flutter 3.47, but tidy_log supports
// 3.32+, where material_ui does not exist yet.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tidy_log/src/flutter/flutter_error_formatter.dart';
import 'package:tidy_log/tidy_log.dart';

/// Real build and layout errors carry the failing element as a
/// `DiagnosticsDebugCreator`, not as the "relevant error-causing widget"
/// text (Flutter only adds that text later, in its property transformers).
/// The location must come from walking up to the nearest widget created in
/// your own code.
void main() {
  late List<String> printed;

  /// Builds [app], captures the errors Flutter reports, then prints them
  /// through the tidy formatter while the failing elements are still mounted.
  Future<String> tidyOutputFor(WidgetTester tester, Widget app) async {
    final captured = <FlutterErrorDetails>[];
    final saved = FlutterError.onError;
    FlutterError.onError = captured.add;
    try {
      await tester.pumpWidget(app);
    } finally {
      FlutterError.onError = saved;
    }
    expect(captured, isNotEmpty, reason: 'the test tree must produce an error');

    printed = [];
    TidyLog.reset();
    TidyLog.configure(enabled: true, color: false, printer: printed.add, projectPackages: const ['my_app']);
    final formatter = FlutterErrorFormatter();
    for (final details in captured) {
      formatter.present(details);
    }
    // Let the follow-on window close so no timer outlives the test.
    await tester.pump(formatter.followOnWindow * 2);
    TidyLog.reset();
    return printed.join('\n');
  }

  /// The 1-based line of this file that contains [marker].
  int lineOf(String marker) =>
      File('test/flutter/widget_location_test.dart').readAsLinesSync().indexWhere((l) => l.contains(marker)) + 1;

  testWidgets('a missing Material points at your InkWell, not at a framework frame', (tester) async {
    final output = await tidyOutputFor(
      tester,
      Directionality(
        textDirection: TextDirection.ltr,
        child: InkWell(onTap: () {}), // <- missing Material
      ),
    );

    expect(output, contains('No Material widget found'));
    final line = lineOf('// <- missing Material');
    expect(output, matches(RegExp('at \\S*widget_location_test\\.dart:$line:\\d+  InkWell')));
  });

  testWidgets('an overflow points at your Row', (tester) async {
    final output = await tidyOutputFor(
      tester,
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 10,
            child: Row(children: [SizedBox(width: 100, height: 10)]), // <- overflowing Row
          ),
        ),
      ),
    );

    expect(output, contains('A RenderFlex overflowed'));
    final line = lineOf('// <- overflowing Row');
    expect(output, matches(RegExp('at \\S*widget_location_test\\.dart:$line:\\d+  Row')));
  });

  group('isProjectSourceFile', () {
    test('your own files count', () {
      expect(isProjectSourceFile('file:///E:/work_space/my_app/lib/app/home.dart'), isTrue);
      expect(isProjectSourceFile('file:///Users/me/my_app/lib/main.dart'), isTrue);
    });

    test('pub cache and SDK files do not', () {
      for (final file in [
        'file:///C:/Users/me/AppData/Local/Pub/Cache/hosted/pub.dev/material_ui-1.11.1/lib/src/ink_well.dart',
        'file:///home/me/.pub-cache/hosted/pub.dev/phone_form_field-12.0.5/lib/src/country_button.dart',
        'file:///C:/flutter/packages/flutter/lib/src/material/ink_well.dart',
        'file:///opt/flutter/bin/cache/pkg/sky_engine/lib/ui/text.dart',
        'file:///Users/me/fvm/versions/3.50.0/packages/flutter/lib/src/widgets/basic.dart',
      ]) {
        expect(isProjectSourceFile(file), isFalse, reason: file);
      }
    });

    test('package: URIs count only for your packages', () {
      expect(isProjectSourceFile('package:my_app/main.dart', projectPackages: const ['my_app']), isTrue);
      expect(isProjectSourceFile('package:material_ui/src/ink_well.dart', projectPackages: const ['my_app']), isFalse);
    });
  });
}
