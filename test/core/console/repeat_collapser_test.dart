import 'package:flutter_test/flutter_test.dart';
import 'package:tidy_log/src/core/console/repeat_collapser.dart';
import 'package:tidy_log/src/core.dart';

Entry line(String text, {String? similar}) => Entry(head: [Span(text)], similarKey: similar);

void main() {
  test('counts identical entries in a row and emits one entry when the run ends', () {
    final collapser = RepeatCollapser();
    final out = [
      for (var i = 0; i < 30; i++) ...collapser.add(line('Sending viewport metrics')),
      ...collapser.add(line('next')),
      ...collapser.flush(),
    ];
    expect(out.map((e) => (e.head.join(), e.repeat)), [('Sending viewport metrics', 30), ('next', 1)]);
  });

  test('folds near-duplicates by similarKey without changing the repeat count', () {
    final collapser = RepeatCollapser();
    final out = [
      ...collapser.add(line('hiddenapi: a', similar: 'k')),
      ...collapser.add(line('hiddenapi: b', similar: 'k')),
      ...collapser.add(line('hiddenapi: c', similar: 'k')),
      ...collapser.add(line('other', similar: 'z')),
      ...collapser.flush(),
    ];
    expect(out.map((e) => (e.head.join(), e.repeat, e.similar)), [('hiddenapi: a', 1, 2), ('other', 1, 0)]);
  });

  test('does not merge the same text when it is not consecutive', () {
    final collapser = RepeatCollapser();
    final out = [
      ...collapser.add(line('a')),
      ...collapser.add(line('b')),
      ...collapser.add(line('a')),
      ...collapser.flush(),
    ];
    expect(out.map((e) => e.repeat), [1, 1, 1]);
  });

  test('flush on an empty collapser emits nothing', () {
    expect(RepeatCollapser().flush(), isEmpty);
  });
}
