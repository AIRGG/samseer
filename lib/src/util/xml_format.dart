/// Best-effort XML pretty-printer for display/export purposes.
///
/// This is a lightweight, regex-based indenter — not a real XML parser. It
/// assumes the input is reasonably well-formed (no `>` inside attribute
/// values, no CDATA spanning multiple "tags"). On anything it can't make
/// sense of it just leaves that line as-is rather than throwing, since this
/// only ever feeds a debug viewer.
String prettyPrintXml(String input, {String indent = '  '}) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) return input;

  final withBreaks = trimmed.replaceAll(RegExp(r'>\s*<'), '>\n<');
  final lines = withBreaks.split('\n');
  final tagPattern = RegExp(r'^<(/)?([^\s>/!?]+)[^>]*?(/)?>$');

  final buffer = StringBuffer();
  var depth = 0;
  for (final rawLine in lines) {
    final line = rawLine.trim();
    if (line.isEmpty) continue;
    final match = tagPattern.firstMatch(line);
    if (match == null || line.startsWith('<?') || line.startsWith('<!')) {
      buffer.writeln(indent * depth + line);
      continue;
    }
    final closing = match.group(1) != null;
    final selfClosing = match.group(3) != null;
    if (closing) {
      depth = depth > 0 ? depth - 1 : 0;
      buffer.writeln(indent * depth + line);
    } else {
      buffer.writeln(indent * depth + line);
      if (!selfClosing) depth += 1;
    }
  }
  return buffer.toString().trimRight();
}
