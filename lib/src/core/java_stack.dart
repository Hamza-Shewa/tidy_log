import 'record_formatter.dart' show framesHidden;

final _javaFrame = RegExp(r'^\s*at (.+)$');
final _exception = RegExp(r'^\s*(?:([A-Za-z_$][\w$]*\.)+)?([A-Z][\w$]*(?:Exception|Error|Throwable))\b(.*)$');

/// Java and Android frames that are rarely where the problem is.
const javaSdkPrefixes = [
  'android.', 'androidx.', 'java.', 'javax.', 'kotlin.', 'kotlinx.', 'com.android.', 'dalvik.', 'libcore.', //
  'sun.', 'io.flutter.', 'com.google.android.', 'com.google.crypto.',
];

/// True when [line] is a Java exception line such as
/// `java.lang.IllegalStateException: Keystore entry missing`.
bool isJavaException(String line) => _exception.hasMatch(line);

/// `java.lang.SecurityException: x` → `SecurityException: x`.
String shortJavaException(String text) {
  final m = _exception.firstMatch(text);
  if (m == null) return text;
  final rest = m[3]!.trim();
  final message = rest.endsWith(':') ? rest.substring(0, rest.length - 1) : rest;
  return '${m[2]}$message';
}

/// A Java or Kotlin stack trace reduced to what the console shows: the first
/// frame outside the Android and Java SDKs, how many frames were left out,
/// and the last `Caused by`.
final class JavaStack {
  const JavaStack._({required this.exception, required this.frame, required this.frameCount, required this.cause});

  /// The first exception line, shortened (`IllegalStateException: …`).
  final String? exception;

  /// The most useful frame: the first one outside [javaSdkPrefixes], or the
  /// top frame when every frame is SDK code.
  final String frame;
  final int frameCount;

  /// The last `Caused by:` exception, shortened.
  final String? cause;

  /// `… 14 frames hidden · caused by IOException: decryption failed`, or an
  /// empty string when there is nothing to add.
  String get note =>
      [if (frameCount > 1) '… ${framesHidden(frameCount - 1)}', if (cause != null) 'caused by $cause'].join(' · ');
}

/// Parses the lines of a Java stack trace. Returns null when no line is a
/// frame (`at …`).
JavaStack? parseJavaStack(Iterable<String> lines) {
  final trimmed = [for (final l in lines) l.trim()];
  final frames = [for (final l in trimmed) ?_javaFrame.firstMatch(l)?[1]];
  if (frames.isEmpty) return null;
  final causes = [
    for (final l in trimmed)
      if (l.startsWith('Caused by: ')) shortJavaException(l.substring('Caused by: '.length)),
  ];
  final exception = trimmed.firstWhere((l) => !l.startsWith('Caused by: ') && _exception.hasMatch(l), orElse: () => '');
  return JavaStack._(
    exception: exception.isEmpty ? null : shortJavaException(exception),
    frame: frames.firstWhere((f) => !javaSdkPrefixes.any(f.startsWith), orElse: () => frames.first),
    frameCount: frames.length,
    cause: causes.lastOrNull,
  );
}
