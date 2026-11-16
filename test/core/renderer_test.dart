import 'package:flutter_test/flutter_test.dart';
import 'package:tidy_log/src/core.dart';

void main() {
  final entry = Entry(
    head: [Level.error.labelSpan, const Span('boom', Tone.errorBold)],
    source: 'FlutterSecureStorage',
    details: [
      [const Span('at lib/a.dart:1:2', Tone.errorBold)],
    ],
  )..repeat = 3;

  test('styled output colours by tone and dims the suffix', () {
    final lines = const Renderer().render(entry);
    expect(lines.first, startsWith('\x1B[1;31mERR \x1B[0m\x1B[1;31mboom\x1B[0m\x1B[90m'));
    expect(lines.first, endsWith('· FlutterSecureStorage  ×3\x1B[0m'));
    expect(lines.last, '    \x1B[1;31mat lib/a.dart:1:2\x1B[0m');
  });

  test('plain output has no escape codes and no native tag, but keeps the count', () {
    final lines = const Renderer(color: false).render(entry);
    expect(lines, ['ERR boom  ×3', '    at lib/a.dart:1:2']);
    expect(lines.join(), isNot(contains('\x1B[')));
  });

  test('maxHeadWidth shortens long heads in the styled view only', () {
    final long = Entry(head: [Span('x' * 50)]);
    expect(stripAnsi(Renderer(maxHeadWidth: 10).render(long).first), '${'x' * 9}…');
    expect(Renderer(color: false, maxHeadWidth: 10).render(long).first, 'x' * 50);
  });

  test('pre-rendered lines pass through, and are stripped in plain mode', () {
    final raw = Entry.raw('\x1B[0m\x1B[31mERR boom\x1B[0m');
    expect(const Renderer().render(raw), ['\x1B[0m\x1B[31mERR boom\x1B[0m']);
    expect(const Renderer(color: false).render(raw), ['ERR boom']);
  });

  test('the clean copy drops the tag suffix of lines the in-app logger styled', () {
    final styled = const Renderer().render(entry).first;
    expect(const Renderer(color: false).render(Entry.raw(styled)), ['ERR boom']);
    expect(const Renderer(color: false, includeSource: true).render(Entry.raw(styled)).single, endsWith('· FlutterSecureStorage  ×3'));
  });

  test('similar count adds a dim line', () {
    final e = Entry(head: [const Span('hiddenapi: x')])..similar = 6;
    expect(const Renderer(color: false).render(e).last, '    ↳ +6 similar');
  });
}
