import 'package:flutter/material.dart';

import '../text/body_document.dart';
import '../text/body_rows.dart';
import '../theme/samseer_theme.dart';
import 'json_viewer.dart';

/// Lazily built rows of a [BodyDocument]: only rows near the viewport are
/// laid out, so multi-megabyte bodies scroll without freezing.
class BodyTextSliver extends StatelessWidget {
  const BodyTextSliver({super.key, required this.document});

  final BodyDocument document;

  @override
  Widget build(BuildContext context) {
    final rows = document.rows;
    final digits = '${_lastLineNumber(rows)}'.length;
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) => BodyRowView(row: rows[index], gutterDigits: digits),
        childCount: rows.length,
      ),
    );
  }

  static int _lastLineNumber(List<BodyRow> rows) {
    for (var i = rows.length - 1; i >= 0; i--) {
      final n = rows[i].lineNumber;
      if (n != null) return n;
    }
    return 1;
  }
}

/// One row: a line number gutter (empty for continuation rows) and the
/// syntax colored text.
class BodyRowView extends StatelessWidget {
  const BodyRowView({super.key, required this.row, required this.gutterDigits});

  final BodyRow row;
  final int gutterDigits;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final colors = SamseerSyntaxColors(cs);
    final mono = SamseerTheme.mono(context);
    final number = row.lineNumber;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SelectionContainer.disabled(
          child: SizedBox(
            width: gutterDigits * 8.0 + 4,
            child: Text(
              number == null ? '' : '$number',
              textAlign: TextAlign.right,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.clip,
              style: mono.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                for (final token in row.tokens)
                  TextSpan(text: token.text, style: _style(token.kind, colors)),
              ],
            ),
            style: mono,
          ),
        ),
      ],
    );
  }

  static TextStyle? _style(BodyTokenKind kind, SamseerSyntaxColors c) {
    switch (kind) {
      case BodyTokenKind.plain:
        return null;
      case BodyTokenKind.key:
        return TextStyle(color: c.key, fontWeight: FontWeight.w600);
      case BodyTokenKind.string:
        return TextStyle(color: c.string);
      case BodyTokenKind.number:
        return TextStyle(color: c.number);
      case BodyTokenKind.boolean:
        return TextStyle(color: c.bool);
      case BodyTokenKind.nullValue:
        return TextStyle(color: c.nullValue);
      case BodyTokenKind.bracket:
        return TextStyle(color: c.bracket);
      case BodyTokenKind.punct:
        return TextStyle(color: c.punct);
    }
  }
}
