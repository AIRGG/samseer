import 'package:flutter/material.dart';

import '../../util/xml_format.dart';
import '../theme/samseer_theme.dart';

/// Pretty-printed, lightly colorized XML viewer. Falls back to the raw
/// string unchanged if [prettyPrintXml] can't make sense of it.
class XmlViewer extends StatelessWidget {
  const XmlViewer({super.key, required this.value});
  final String value;

  @override
  Widget build(BuildContext context) {
    final formatted = prettyPrintXml(value);
    final cs = Theme.of(context).colorScheme;
    return SelectableText.rich(
      TextSpan(children: _colorize(formatted, cs)),
      style: SamseerTheme.mono(context),
    );
  }

  static final RegExp _tagPattern = RegExp(r'(</?)([\w:.-]+)([^>]*?)(/?>)');

  List<InlineSpan> _colorize(String text, ColorScheme cs) {
    final spans = <InlineSpan>[];
    var last = 0;
    for (final match in _tagPattern.allMatches(text)) {
      if (match.start > last) {
        spans.add(TextSpan(text: text.substring(last, match.start)));
      }
      spans
        ..add(TextSpan(
          text: match.group(1),
          style: TextStyle(color: cs.onSurfaceVariant),
        ))
        ..add(TextSpan(
          text: match.group(2),
          style: TextStyle(color: cs.primary, fontWeight: FontWeight.w600),
        ))
        ..add(TextSpan(
          text: match.group(3),
          style: const TextStyle(color: Color(0xFFF59E0B)),
        ))
        ..add(TextSpan(
          text: match.group(4),
          style: TextStyle(color: cs.onSurfaceVariant),
        ));
      last = match.end;
    }
    if (last < text.length) {
      spans.add(TextSpan(text: text.substring(last)));
    }
    return spans;
  }
}
