import '../entry.dart';
import '../flutter_messages.dart';
import '../level.dart';
import '../renderer.dart' show startsWithAnsi;
import '../stack_trimmer.dart';
import '../record_formatter.dart';
import 'block_folder.dart';
import 'config.dart';
import 'logcat_line.dart';
import 'noise_filter.dart';
import 'pretty_http.dart';
import 'redactor.dart';
import 'repeat_collapser.dart';
import 'restyler.dart';

final _boxStart = RegExp(r'^══╡ EXCEPTION CAUGHT BY (.+?) ╞═*$');
final _boxEnd = RegExp(r'^═{20,}$');
final _again = RegExp(r'^Another exception was thrown: (.*)$');
final _restarted = RegExp(r'^(Restarted application|Reloaded \d+(?: of \d+)? librar(?:y|ies)) in ([\d,]+)\s?ms\b');
final _sourceLocation = RegExp(r'((?:package:|file://)\S+?\.dart|lib/\S+?\.dart):(\d+):(\d+)');

/// The whole cleaner: feed it the Flutter tool's text output line by line,
/// get back [Entry] values ready to render.
///
/// It is synchronous and has no timers or IO, so it is easy to test. The
/// wrapper calls [flush] when the output goes quiet, so held-back lines
/// (open blocks, repeat counts) still show up promptly.
final class ConsolePipeline {
  ConsolePipeline(this.config)
    : _filter = NoiseFilter(config),
      _redactor = Redactor(config.redactKeys),
      _restyler = Restyler(config),
      _http = PrettyHttpPairer(redact: Redactor(config.redactKeys).apply, rules: config.httpRules);

  final TidyConfig config;
  final NoiseFilter _filter;
  final Redactor _redactor;
  final Restyler _restyler;
  final PrettyHttpPairer _http;
  final _folder = BlockFolder();
  final _collapser = RepeatCollapser();
  final _seenPids = <int>{};
  int? _currentPid;
  List<String>? _box;
  String? _boxCaughtBy;

  List<Entry> add(String line) {
    final out = <Entry>[];
    if (_box != null) {
      _box!.add(line);
      if (_boxEnd.hasMatch(line)) out.addAll(_emit(_frameworkError()));
      return out;
    }

    final logcat = LogcatLine.tryParse(line);
    if (logcat == null) {
      out.addAll(_closeBlocks(_folder.flush()));
      final start = _boxStart.firstMatch(line);
      if (start != null) {
        _box = [];
        _boxCaughtBy = start[1];
        return out;
      }
      out.addAll(_emit(_rawLine(line)));
      return out;
    }

    final isNewProcess = _seenPids.add(logcat.pid);
    if (!_filter.shows(logcat)) {
      if (isNewProcess) out.addAll([..._closeBlocks(_folder.flush()), ..._newProcess(logcat.pid)]);
      return out;
    }
    out.addAll(_closeBlocks(_folder.add(logcat)));
    if (isNewProcess) out.addAll(_newProcess(logcat.pid));
    return out;
  }

  /// Emits everything held back.
  /// Ends the run: everything [flush] emits, plus HTTP requests that never
  /// got their response (an idle [flush] keeps waiting for those).
  List<Entry> finish() => [...flush(), for (final entry in _http.finish()) ..._emit(entry), ..._collapser.flush()];

  List<Entry> flush() => [
    ..._closeBlocks(_folder.flush()),
    if (_box != null) ..._emit(_frameworkError()),
    ..._collapser.flush(),
  ];

  List<Entry> _newProcess(int pid) {
    _currentPid = pid;
    return _emit(Entry.divider('app started · pid $pid'));
  }

  List<Entry> _closeBlocks(List<Block> blocks) => [for (final block in blocks) ..._closeBlock(block)];

  List<Entry> _closeBlock(Block block) {
    // Blank Dart lines (pretty loggers print one before every box) are noise.
    if (block.first.isDart && block.messages.every((m) => m.trim().isEmpty)) return const [];
    // A blank line that only separated this block from the next box.
    while (block.messages.length > 1 && block.messages.last.trim().isEmpty) {
      block.messages.removeLast();
    }
    final box = block.isPrettyBox ? PrettyBox.parse(block.messages) : null;
    if (box != null) return [for (final entry in _http.add(box)) ..._emit(entry)];
    return _emit(_restyler.restyle(block, currentPid: _currentPid));
  }

  List<Entry> _emit(Entry entry) => _collapser.add(_redact(entry));

  Entry _redact(Entry entry) {
    if (entry.preRendered) return entry;
    List<Span> map(List<Span> spans) => [for (final s in spans) Span(_redactor.apply(s.text), s.tone)];
    return Entry(
      head: map(entry.head),
      source: entry.source,
      details: [for (final d in entry.details) map(d)],
      similarKey: entry.similarKey,
    );
  }

  Entry _rawLine(String line) {
    if (startsWithAnsi(line)) return Entry.raw(line);
    final again = _again.firstMatch(line);
    if (again != null) {
      final message = stripRenderIds(again[1]!);
      return Entry(
        head: [Level.error.labelSpan, Span(message, Tone.error)],
        source: 'thrown again',
        // Follow-on layout errors name a different render object each time;
        // fold them into the first one as "↳ +N similar".
        similarKey: isFollowOnError(message) ? 'follow-on layout error' : null,
      );
    }
    final restart = _restarted.firstMatch(line);
    if (restart != null) {
      final what = restart[1]!.startsWith('Restarted') ? 'hot restart' : 'hot reload';
      return Entry.divider('$what · ${restart[2]} ms');
    }
    return Entry(head: [Span(line)]);
  }

  /// Folds Flutter's `══╡ EXCEPTION CAUGHT BY … ╞══` box into one entry.
  Entry _frameworkError() {
    final lines = _box!;
    final caughtBy = _boxCaughtBy ?? 'Flutter';
    _box = null;
    _boxCaughtBy = null;

    final thrown = lines.indexWhere((l) => l.startsWith('The following '));
    final body = lines.skip(thrown + 1).toList();
    final message = body.firstWhere((l) => l.trim().isNotEmpty, orElse: () => 'Flutter error').trim();
    final notes = body
        .skip(body.indexOf(message) + 1)
        .takeWhile((l) => l.trim().isNotEmpty)
        .take(4)
        .map((l) => l.trim())
        .toList();

    var stack = trimStackText(
      lines.where((l) => RegExp(r'^#\d+\s').hasMatch(l)).join('\n'),
      projectPackages: config.projectPackages,
    );
    final widgetAt = lines.indexWhere((l) => l.contains('relevant error-causing widget was'));
    final located = (widgetAt >= 0 ? lines.skip(widgetAt) : lines)
        .map(_sourceLocation.firstMatch)
        .firstWhere((m) => m != null, orElse: () => null);
    if (located != null && (stack.location == null || widgetAt >= 0)) {
      final uri = Uri.parse(located[1]!);
      final widget = widgetAt >= 0 ? lines[widgetAt + 1].trim().split(' ').first.replaceAll(RegExp(r':$'), '') : '';
      stack = TrimmedStack(
        location: FrameRef(
          '${displayPath(uri, appPackage: config.projectPackages.first)}:${located[2]}:${located[3]}',
          widget,
        ),
        trail: stack.trail,
        hidden: stack.hidden,
      );
    }

    return Entry(
      head: [Level.error.labelSpan, Span(message, Tone.errorBold)],
      source: 'caught by $caughtBy'.toLowerCase(),
      details: [
        for (final note in notes) [Span(note, Tone.secondary)],
        ...stackDetails(stack, Level.error),
        if (stack.location == null) [Span('┊ … ${lines.length} lines hidden', Tone.dim)],
      ],
    );
  }
}
