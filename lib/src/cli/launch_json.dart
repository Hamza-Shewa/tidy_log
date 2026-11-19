import 'dart:convert';

/// Path of the VS Code launcher, relative to the project root.
const launcherPath = '.vscode/tidy_flutter';

/// Suffix added to the name of each tidy twin config.
const twinSuffix = ' (tidy logs)';

/// The fields that route a Dart launch config through the tidy_log runner.
const tidyToolFields = <String, Object>{'customTool': '\${workspaceFolder}/$launcherPath', 'customToolReplacesArgs': 0};
const _windowsTool = '\${workspaceFolder}\\.vscode\\tidy_flutter.bat';

/// The config written when the project has no Dart launch config yet.
Map<String, Object?> defaultTidyConfig() => {
  'name': 'Flutter$twinSuffix',
  'type': 'dart',
  'request': 'launch',
  'program': 'lib/main.dart',
  ...tidyToolFields,
  'windows': {'customTool': _windowsTool},
};

/// What [addTidyTwins] or [removeTidyTwins] did.
final class LaunchEdit {
  const LaunchEdit(
    this.text, {
    this.added = const [],
    this.removed = const [],
    this.skipped = const [],
    this.notes = const [],
    this.kept = const [],
    this.moved = const [],
    this.leftEmpty = false,
  });

  /// The new file content (unchanged when nothing was added or removed).
  final String text;
  final List<String> added;
  final List<String> removed;

  /// Configs left alone, with the reason (`name: reason`).
  final List<String> skipped;

  /// Other things the user should know, one sentence each.
  final List<String> notes;

  /// After a removal: the names of tidy configs that were kept because they
  /// were changed after setup added them. They still use the launchers.
  final List<String> kept;

  /// Tidy configs that were already there and were moved to the top (set up
  /// by a version that put them last).
  final List<String> moved;

  bool get changed => added.isNotEmpty || removed.isNotEmpty || moved.isNotEmpty;

  /// After a removal: the file is back to the empty file setup creates from
  /// scratch (no other configs, no comments), so it can be deleted.
  final bool leftEmpty;
}

/// Thrown when launch.json cannot be edited safely.
final class LaunchJsonException implements Exception {
  const LaunchJsonException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Adds a `<name> (tidy logs)` twin of every Flutter app launch (`"type":
/// "dart"`, `run` or `attach`) in [source] (the text of
/// `.vscode/launch.json`, or null when it is missing).
///
/// Test configs (a `program` under `test/` or `integration_test/`, or
/// `"templateFor": "test"`) and plain Dart programs (a `program` outside
/// `lib/`) get none: tidy_log only tidies `flutter run` and `attach`. When
/// two configs share a name, the second twin is `<name> (tidy logs 2)`.
///
/// The tidy configs go first in the list, so VS Code picks a tidy launch by
/// default. They are inserted as text right after `"configurations": [`, so
/// comments and formatting elsewhere stay byte for byte. Tidy configs that
/// are already there but not first (earlier versions put them last) are
/// moved up, text unchanged. Running it again changes nothing.
LaunchEdit addTidyTwins(String? source) {
  try {
    return _addTidyTwins(source);
  } on FormatException catch (e) {
    throw LaunchJsonException('launch.json is not valid JSON: ${e.message}');
  }
}

LaunchEdit _addTidyTwins(String? source) {
  if (source == null || source.trim().isEmpty) {
    final config = defaultTidyConfig();
    final text = const JsonEncoder.withIndent('  ').convert({
      'version': '0.2.0',
      'configurations': [config],
    });
    return LaunchEdit('$text\n', added: [config['name']! as String]);
  }

  final array = _findConfigurations(source);
  final configs = [for (final e in array.elements) _decode(source.substring(e.start, e.end))];
  final names = {for (final c in configs) c['name']};

  final twins = <Map<String, Object?>>[];
  final skipped = <String>[];
  final notes = <String>[];
  for (final (config, twinName) in _sources(configs)) {
    final name = _name(config);
    if (names.contains(twinName)) continue;
    final notTidied = _notTidied(config);
    if (notTidied != null) {
      skipped.add('$name: $notTidied');
      continue;
    }
    if (config['customTool'] != null) {
      skipped.add('$name: already uses customTool ${config['customTool']}');
      continue;
    }
    final windowsTool = _windowsToolOf(config);
    if (windowsTool != null) {
      notes.add(
        'launch config "$twinName" keeps its own windows.customTool ($windowsTool), '
        'so on Windows it runs without tidy_log',
      );
    }
    twins.add(_twin(config, twinName));
  }
  final fallback = defaultTidyConfig();
  if (twins.isEmpty && !configs.any(isTidyConfig) && !names.contains(fallback['name'])) twins.add(fallback);

  // The tidy configs in the order they should open the list: each in the
  // place of the config it mirrors, then any others (the default config, a
  // renamed one) in their current order.
  final existing = [
    for (var i = 0; i < configs.length; i++)
      if (isTidyConfig(configs[i]))
        (index: i, name: _name(configs[i]), text: source.substring(array.elements[i].start, array.elements[i].end)),
  ];
  final encoder = JsonEncoder.withIndent(_indentStep(source, array));
  final front = <({String name, String? text, Map<String, Object?>? config})>[
    for (final (_, twinName) in _sources(configs))
      if (existing.where((e) => e.name == twinName).firstOrNull case final e?)
        (name: e.name, text: e.text, config: null)
      else if (twins.where((t) => t['name'] == twinName).firstOrNull case final t?)
        (name: twinName, text: null, config: t),
  ];
  for (final e in existing) {
    if (!front.any((f) => f.name == e.name)) front.add((name: e.name, text: e.text, config: null));
  }
  for (final t in twins) {
    if (!front.any((f) => f.name == t['name'])) front.add((name: t['name']! as String, text: null, config: t));
  }

  // A tidy config moves when it does not already sit where it belongs.
  final moved = [
    for (final e in existing)
      if (front.indexWhere((f) => f.name == e.name) != e.index) e.name,
  ];
  if (twins.isEmpty && moved.isEmpty) return LaunchEdit(source, skipped: skipped);

  // Take the existing tidy configs out, then put every tidy config first.
  var text = source;
  while (true) {
    final current = _findConfigurations(text);
    final index = current.elements.indexWhere((e) => isTidyConfig(_decode(text.substring(e.start, e.end))));
    if (index < 0) break;
    text = _removeElement(text, current.elements, index);
  }
  final blocks = [
    for (final f in front)
      if (f.text case final text?) (text: text, encoded: false) else (text: encoder.convert(f.config), encoded: true),
  ];
  return LaunchEdit(
    _insertFirst(text, _findConfigurations(text), blocks),
    added: [for (final t in twins) t['name']! as String],
    moved: moved,
    skipped: skipped,
    notes: notes,
  );
}

String _name(Map<String, Object?> config) => '${config['name'] ?? 'Flutter'}';

/// `<name> (tidy logs)` or, for a later config with the same name,
/// `<name> (tidy logs 2)` and so on.
final _twinName = RegExp(r'^(.*) \(tidy logs(?: (\d+))?\)$');

/// Every config that can have a twin (a Dart config that is not a tidy
/// config or named like a twin), with the name its twin gets.
List<(Map<String, Object?>, String)> _sources(List<Map<String, Object?>> configs) {
  final seen = <String, int>{};
  return [
    for (final config in configs)
      if (config['type'] == 'dart' && !isTidyConfig(config) && !_twinName.hasMatch(_name(config)))
        (config, _nthTwinName(_name(config), seen[_name(config)] = (seen[_name(config)] ?? 0) + 1)),
  ];
}

String _nthTwinName(String name, int n) => n == 1 ? '$name$twinSuffix' : '$name (tidy logs $n)';

/// Why [config] gets no twin, or null when it is a Flutter app launch.
String? _notTidied(Map<String, Object?> config) {
  List<String> segments(Object? path) => path is String ? path.replaceAll(r'\', '/').split('/') : const [];
  bool isTest(List<String> s) => s.contains('test') || s.contains('integration_test');
  final program = segments(config['program']);
  final template = config['templateFor'];
  if (isTest(program) || (template is String && (template == 'test' || isTest(segments(template))))) {
    return 'a test config (tidy_log only tidies flutter run and attach)';
  }
  if (program.isNotEmpty && !program.contains('lib')) return 'not a Flutter app (program ${config['program']})';
  return null;
}

String? _windowsToolOf(Map<String, Object?> config) {
  final windows = config['windows'];
  return windows is Map && windows['customTool'] != null ? '${windows['customTool']}' : null;
}

/// Removes every config that [addTidyTwins] added and that is still as it
/// was written. A tidy config that was changed since is kept and reported
/// in [LaunchEdit.kept], as an edited launcher script is. Other text is left
/// as it is.
LaunchEdit removeTidyTwins(String source) {
  try {
    return _removeTidyTwins(source);
  } on FormatException catch (e) {
    throw LaunchJsonException('launch.json is not valid JSON: ${e.message}');
  }
}

LaunchEdit _removeTidyTwins(String source) {
  var text = source;
  final removed = <String>[];
  while (true) {
    final array = _findConfigurations(text);
    final configs = [for (final e in array.elements) _decode(text.substring(e.start, e.end))];
    final index = configs.indexWhere((c) => isTidyConfig(c) && _asWritten(c, configs));
    if (index < 0) break;
    removed.add('${configs[index]['name']}');
    text = _removeElement(text, array.elements, index);
  }
  final kept = [
    for (final e in _findConfigurations(text).elements)
      if (_decode(text.substring(e.start, e.end)) case final c when isTidyConfig(c)) '${c['name']}',
  ];
  return LaunchEdit(
    text,
    removed: removed,
    kept: kept,
    skipped: [
      for (final name in kept) '$name: changed since setup added it; delete it by hand if you no longer need it',
    ],
    leftEmpty: removed.isNotEmpty && _isEmptyDefault(text),
  );
}

/// Whether tidy config [twin] is exactly what [addTidyTwins] wrote for its
/// source in [configs] (or the default config), also as older versions
/// wrote it (they replaced a `windows.customTool`).
bool _asWritten(Map<String, Object?> twin, List<Map<String, Object?>> configs) {
  final name = '${twin['name']}';
  final source = [
    for (final (config, twinName) in _sources(configs))
      if (twinName == name) config,
  ].firstOrNull;
  return [
    if (source != null) ...[_twin(source, name), _twin(source, name, replaceWindowsTool: true)],
    if (name == defaultTidyConfig()['name']) defaultTidyConfig(),
  ].any((written) => _sameJson(written, twin));
}

bool _sameJson(Object? a, Object? b) {
  if (a is Map && b is Map) {
    return a.length == b.length && a.keys.every((k) => b.containsKey(k) && _sameJson(a[k], b[k]));
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_sameJson(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}

/// Removes element [index] and only what belongs to it: its own comma, and
/// its line when nothing else is on that line. Comments between elements
/// stay. When the element has no comma of its own (it was last), the comma
/// that separated it from the element before goes instead.
String _removeElement(String text, List<_Element> elements, int index) {
  final element = elements[index];
  final ownComma = element.commaEnd > element.end;
  final lineStart = text.lastIndexOf('\n', element.start - 1) + 1;
  final aloneOnLine = text.substring(lineStart, element.start).trim().isEmpty;

  var from = aloneOnLine ? lineStart : element.start;
  var to = ownComma ? element.commaEnd : element.end;
  if (aloneOnLine) {
    var j = to;
    while (j < text.length && (text[j] == ' ' || text[j] == '\t')) {
      j++;
    }
    if (text.startsWith('\r\n', j)) {
      to = j + 2;
    } else if (j < text.length && text[j] == '\n') {
      to = j + 1;
    } else if (j >= text.length) {
      to = j;
    } else {
      from = element.start; // something follows on the same line: keep the line
    }
  }
  var result = text.replaceRange(from, to, '');
  if (!ownComma && index > 0) {
    final previous = elements[index - 1];
    if (previous.commaEnd > previous.end) result = result.replaceRange(previous.commaEnd - 1, previous.commaEnd, '');
  }
  return result;
}

/// Whether [text] is just `{"version": "0.2.0", "configurations": []}`
/// with no comments: what setup would have created from scratch.
bool _isEmptyDefault(String text) {
  final stripped = stripJsonc(text);
  if (stripped.replaceAll(RegExp(r'\s'), '') != text.replaceAll(RegExp(r'\s'), '')) return false; // has comments
  final decoded = jsonDecode(stripped);
  return decoded is Map &&
      decoded.length == 2 &&
      decoded['version'] == '0.2.0' &&
      decoded['configurations'] is List &&
      (decoded['configurations'] as List).isEmpty;
}

/// Whether [config] runs through the launcher that setup writes: its
/// `customTool` is exactly `${workspaceFolder}/.vscode/tidy_flutter`. Configs
/// pointing anywhere else (a hand-made `build/tidy_flutter`, a renamed copy)
/// are not ours and are never removed.
bool isTidyConfig(Map<String, Object?> config) => config['customTool'] == tidyToolFields['customTool'];

/// The tidy twin of [config], named [name]. A `windows.customTool` of its
/// own is kept unless [replaceWindowsTool] (what earlier versions did).
Map<String, Object?> _twin(Map<String, Object?> config, String name, {bool replaceWindowsTool = false}) {
  final windows = config['windows'];
  final keepWindowsTool = !replaceWindowsTool && _windowsToolOf(config) != null;
  return {
    ...config,
    'name': name,
    ...tidyToolFields,
    'windows': {if (windows is Map) ...windows, if (!keepWindowsTool) 'customTool': _windowsTool},
  };
}

/// The file's own indentation: the closing bracket's indent, and the indent
/// of an element of the configurations list.
({String close, String element}) _indents(String source, _ArrayInfo array) {
  final close = _indentBefore(source, array.close) ?? '  ';
  final unit = close.contains('\t') ? '\t' : '  ';
  final element = array.elements.isEmpty
      ? '$close$unit'
      : (_indentBefore(source, array.elements.first.start) ?? '$close$unit');
  return (close: close, element: element);
}

/// The file's own indent step (tabs or n spaces), so new configs look like
/// the rest.
String _indentStep(String source, _ArrayInfo array) {
  final (:close, :element) = _indents(source, array);
  return element.length > close.length && element.startsWith(close)
      ? element.substring(close.length)
      : (close.contains('\t') ? '\t' : '  ');
}

/// Inserts [blocks] as the first elements of the configurations list, right
/// after its `[`. A block is either text cut from the file (already indented
/// for this list) or a newly encoded config (`\n` line breaks, no outer
/// indent), which gets the file's line breaks and indent.
String _insertFirst(String source, _ArrayInfo array, List<({String text, bool encoded})> blocks) {
  final nl = source.contains('\r\n') ? '\r\n' : '\n';
  final (:close, :element) = _indents(source, array);
  final body = [
    for (final b in blocks) b.encoded ? b.text.replaceAll('\n', '$nl$element') : b.text,
  ].join(',$nl$element');
  final text = array.elements.isEmpty ? '$nl$element$body$nl$close' : '$nl$element$body,';
  return source.replaceRange(array.open + 1, array.open + 1, text);
}

/// The whitespace before [offset] when [offset] is the first character on
/// its line, otherwise null.
String? _indentBefore(String source, int offset) {
  final lineStart = source.lastIndexOf('\n', offset - 1) + 1;
  final before = source.substring(lineStart, offset).replaceAll('\r', '');
  return before.trim().isEmpty ? before : null;
}

Map<String, Object?> _decode(String elementText) {
  try {
    final value = jsonDecode(stripJsonc(elementText));
    return value is Map<String, Object?> ? value : const {};
  } on FormatException {
    return const {};
  }
}

/// Removes `//` and `/* */` comments and trailing commas, which VS Code
/// accepts in its JSON files but [jsonDecode] does not.
String stripJsonc(String text) {
  final out = StringBuffer();
  var i = 0;
  while (i < text.length) {
    final c = text[i];
    if (c == '"') {
      final end = _stringEnd(text, i);
      out.write(text.substring(i, end));
      i = end;
    } else if (text.startsWith('//', i) || text.startsWith('/*', i)) {
      i = _skipComment(text, i);
    } else if (c == ',') {
      final next = _skip(text, i + 1);
      if (next < text.length && (text[next] == '}' || text[next] == ']')) {
        i++;
      } else {
        out.write(c);
        i++;
      }
    } else {
      out.write(c);
      i++;
    }
  }
  return out.toString();
}

final class _Element {
  _Element(this.start, this.end, this.commaEnd);
  final int start;
  final int end;

  /// Just past the comma that follows this element, or [end] when none does.
  final int commaEnd;
}

final class _ArrayInfo {
  _ArrayInfo(this.open, this.close, this.elements, this.trailingComma);
  final int open;
  final int close;
  final List<_Element> elements;
  final bool trailingComma;
}

/// Finds the root object's `configurations` array, with the offsets of each
/// element, by scanning the text (strings and comments are skipped).
_ArrayInfo _findConfigurations(String s) {
  var i = _skip(s, 0);
  if (i >= s.length || s[i] != '{') throw const LaunchJsonException('launch.json does not start with an object.');
  i = _skip(s, i + 1);
  while (i < s.length && s[i] != '}') {
    if (s[i] != '"') throw LaunchJsonException('Unexpected "${s[i]}" in launch.json at offset $i.');
    final keyEnd = _stringEnd(s, i);
    final key = jsonDecode(s.substring(i, keyEnd));
    i = _skip(s, keyEnd);
    if (i >= s.length || s[i] != ':') throw LaunchJsonException('Expected ":" in launch.json at offset $i.');
    i = _skip(s, i + 1);
    if (key == 'configurations' && i < s.length && s[i] == '[') return _array(s, i);
    i = _skip(s, _valueEnd(s, i));
    if (i < s.length && s[i] == ',') i = _skip(s, i + 1);
  }
  throw const LaunchJsonException('launch.json has no "configurations" list.');
}

_ArrayInfo _array(String s, int open) {
  final elements = <_Element>[];
  var i = _skip(s, open + 1);
  var trailingComma = false;
  while (i < s.length && s[i] != ']') {
    final start = i;
    final end = _valueEnd(s, i);
    i = _skip(s, end);
    var commaEnd = end;
    if (i < s.length && s[i] == ',') {
      commaEnd = i + 1;
      i = _skip(s, i + 1);
      trailingComma = i < s.length && s[i] == ']';
    }
    elements.add(_Element(start, end, commaEnd));
  }
  if (i >= s.length) throw const LaunchJsonException('launch.json: "configurations" is not closed.');
  return _ArrayInfo(open, i, elements, trailingComma);
}

/// End offset of the JSON value starting at [i].
int _valueEnd(String s, int i) {
  if (i >= s.length) throw const LaunchJsonException('launch.json ends early.');
  final c = s[i];
  if (c == '"') return _stringEnd(s, i);
  if (c == '{' || c == '[') {
    final close = c == '{' ? '}' : ']';
    var j = _skip(s, i + 1);
    while (j < s.length && s[j] != close) {
      j = _skip(s, _valueEnd(s, j));
      if (j < s.length && (s[j] == ',' || s[j] == ':')) j = _skip(s, j + 1);
    }
    if (j >= s.length) throw const LaunchJsonException('launch.json has an unclosed bracket.');
    return j + 1;
  }
  var j = i;
  while (j < s.length && !',:]} \t\r\n/'.contains(s[j])) {
    j++;
  }
  if (j == i) throw LaunchJsonException('Unexpected "${s[i]}" in launch.json at offset $i.');
  return j;
}

int _stringEnd(String s, int i) {
  var j = i + 1;
  while (j < s.length && s[j] != '"') {
    j += s[j] == r'\' ? 2 : 1;
  }
  if (j >= s.length) throw const LaunchJsonException('launch.json has an unclosed string.');
  return j + 1;
}

/// Skips whitespace and comments.
int _skip(String s, int i) {
  while (i < s.length) {
    if (' \t\r\n'.contains(s[i])) {
      i++;
    } else if (s.startsWith('//', i) || s.startsWith('/*', i)) {
      i = _skipComment(s, i);
    } else {
      break;
    }
  }
  return i;
}

int _skipComment(String s, int i) {
  if (s.startsWith('//', i)) {
    final end = s.indexOf('\n', i);
    return end < 0 ? s.length : end;
  }
  final end = s.indexOf('*/', i + 2);
  return end < 0 ? s.length : end + 2;
}
