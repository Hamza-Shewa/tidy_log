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
  const LaunchEdit(this.text, {this.added = const [], this.removed = const [], this.skipped = const []});

  /// The new file content (unchanged when nothing was added or removed).
  final String text;
  final List<String> added;
  final List<String> removed;

  /// Configs left alone, with the reason (`name: reason`).
  final List<String> skipped;

  bool get changed => added.isNotEmpty || removed.isNotEmpty;
}

/// Thrown when launch.json cannot be edited safely.
final class LaunchJsonException implements Exception {
  const LaunchJsonException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Adds a `<name> (tidy logs)` twin of every `"type": "dart"` config in
/// [source] (the text of `.vscode/launch.json`, or null when it is missing).
///
/// The twins are inserted as text after the last config, so comments and
/// formatting elsewhere in the file stay byte for byte. Running it again
/// adds nothing.
LaunchEdit addTidyTwins(String? source) {
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
  for (final config in configs) {
    final name = '${config['name'] ?? 'Flutter'}';
    if (config['type'] != 'dart' || isTidyConfig(config) || name.endsWith(twinSuffix)) continue;
    if (names.contains('$name$twinSuffix')) continue;
    if (config['customTool'] != null) {
      skipped.add('$name: already uses customTool ${config['customTool']}');
      continue;
    }
    twins.add(_twin(config));
  }
  if (twins.isEmpty && !configs.any(isTidyConfig)) twins.add(defaultTidyConfig());
  if (twins.isEmpty) return LaunchEdit(source, skipped: skipped);

  return LaunchEdit(
    _insert(source, array, twins),
    added: [for (final t in twins) t['name']! as String],
    skipped: skipped,
  );
}

/// Removes every config that [addTidyTwins] would have added (any config
/// whose `customTool` is the tidy launcher). Other text is left as it is.
LaunchEdit removeTidyTwins(String source) {
  var text = source;
  final removed = <String>[];
  while (true) {
    final array = _findConfigurations(text);
    final index = array.elements.indexWhere((e) => isTidyConfig(_decode(text.substring(e.start, e.end))));
    if (index < 0) break;
    final element = array.elements[index];
    removed.add('${_decode(text.substring(element.start, element.end))['name']}');
    final (from, to) = index > 0
        ? (array.elements[index - 1].end, element.end)
        : (element.start, array.elements.length > 1 ? array.elements[1].start : element.commaEnd);
    text = text.replaceRange(from, to, '');
  }
  return LaunchEdit(text, removed: removed);
}

/// Whether [config] runs through the launcher that setup writes. Configs
/// pointing anywhere else (for example a hand-made `build/tidy_flutter`)
/// are not ours and are never removed.
bool isTidyConfig(Map<String, Object?> config) => '${config['customTool'] ?? ''}'.contains(launcherPath);

Map<String, Object?> _twin(Map<String, Object?> config) {
  final windows = config['windows'];
  return {
    ...config,
    'name': '${config['name'] ?? 'Flutter'}$twinSuffix',
    ...tidyToolFields,
    'windows': {if (windows is Map) ...windows, 'customTool': _windowsTool},
  };
}

String _insert(String source, _ArrayInfo array, List<Map<String, Object?>> twins) {
  final closeIndent = _indentBefore(source, array.close) ?? '  ';
  final elementIndent = array.elements.isEmpty
      ? '$closeIndent  '
      : (_indentBefore(source, array.elements.first.start) ?? '$closeIndent  ');
  final step = elementIndent.length > closeIndent.length ? ' ' * (elementIndent.length - closeIndent.length) : '  ';
  final encoder = JsonEncoder.withIndent(step);
  final blocks = [for (final t in twins) encoder.convert(t).replaceAll('\n', '\n$elementIndent')];

  if (array.elements.isEmpty) {
    final text = '\n$elementIndent${blocks.join(',\n$elementIndent')}\n$closeIndent';
    return source.replaceRange(array.open + 1, array.open + 1, text);
  }
  final last = array.elements.last;
  final at = array.trailingComma ? last.commaEnd : last.end;
  final text =
      '${array.trailingComma ? '' : ','}\n$elementIndent${blocks.join(',\n$elementIndent')}${array.trailingComma ? ',' : ''}';
  return source.replaceRange(at, at, text);
}

/// The whitespace before [offset] when [offset] is the first character on
/// its line, otherwise null.
String? _indentBefore(String source, int offset) {
  final lineStart = source.lastIndexOf('\n', offset - 1) + 1;
  final before = source.substring(lineStart, offset);
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
