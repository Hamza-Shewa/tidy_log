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

  bool get changed => added.isNotEmpty || removed.isNotEmpty;

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
/// The twins are inserted as text after the last config, so comments and
/// formatting elsewhere in the file stay byte for byte. Running it again
/// adds nothing.
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
  if (twins.isEmpty) return LaunchEdit(source, skipped: skipped);

  return LaunchEdit(
    _insert(source, array, twins),
    added: [for (final t in twins) t['name']! as String],
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

String _insert(String source, _ArrayInfo array, List<Map<String, Object?>> twins) {
  final nl = source.contains('\r\n') ? '\r\n' : '\n';
  final closeIndent = _indentBefore(source, array.close) ?? '  ';
  final unit = closeIndent.contains('\t') ? '\t' : '  ';
  final elementIndent = array.elements.isEmpty
      ? '$closeIndent$unit'
      : (_indentBefore(source, array.elements.first.start) ?? '$closeIndent$unit');
  // The file's own indent step (tabs or n spaces), so twins look like the rest.
  final step = elementIndent.length > closeIndent.length && elementIndent.startsWith(closeIndent)
      ? elementIndent.substring(closeIndent.length)
      : unit;
  final encoder = JsonEncoder.withIndent(step);
  final blocks = [for (final t in twins) encoder.convert(t).replaceAll('\n', '$nl$elementIndent')];

  if (array.elements.isEmpty) {
    final text = '$nl$elementIndent${blocks.join(',$nl$elementIndent')}$nl$closeIndent';
    return source.replaceRange(array.open + 1, array.open + 1, text);
  }
  final last = array.elements.last;
  final at = array.trailingComma ? last.commaEnd : last.end;
  final text =
      '${array.trailingComma ? '' : ','}$nl$elementIndent${blocks.join(',$nl$elementIndent')}${array.trailingComma ? ',' : ''}';
  return source.replaceRange(at, at, text);
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
