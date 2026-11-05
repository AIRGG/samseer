import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

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
    final digits = '${document.lineCount}'.length;
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) => BodyRowView(
          row: rows[index],
          gutterDigits: digits,
          endsLine:
              index + 1 < rows.length && rows[index + 1].lineNumber != null,
        ),
        childCount: rows.length,
      ),
    );
  }
}

/// One row: a line number gutter (empty for continuation rows) and the
/// syntax colored text.
///
/// Each row is its own selectable, and Flutter joins selected pieces with no
/// separator, so the row adds the line break itself: a row that ends a source
/// line copies with a trailing `\n` when the selection runs through its end.
/// Continuation rows join the next row directly.
class BodyRowView extends StatefulWidget {
  const BodyRowView({
    super.key,
    required this.row,
    required this.gutterDigits,
    this.endsLine = false,
  });

  final BodyRow row;
  final int gutterDigits;

  /// Whether a new source line follows this row.
  final bool endsLine;

  @override
  State<BodyRowView> createState() => _BodyRowViewState();
}

class _BodyRowViewState extends State<BodyRowView> {
  final _RowSelectionDelegate _selection = _RowSelectionDelegate();

  @override
  void dispose() {
    _selection.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final colors = SamseerSyntaxColors(cs);
    final mono = SamseerTheme.mono(context);
    final number = widget.row.lineNumber;
    final tokens = widget.row.tokens;
    final empty = tokens.every((t) => t.text.isEmpty);
    _selection
      ..endsLine = widget.endsLine
      ..empty = empty;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SelectionContainer.disabled(
          child: SizedBox(
            width: widget.gutterDigits * 8.0 + 4,
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
          child: SelectionContainer(
            delegate: _selection,
            // An empty line still needs a selectable to carry its line break.
            child: empty
                ? Text(_emptyRowText, style: mono)
                : Text.rich(
                    TextSpan(
                      children: [
                        for (final token in tokens)
                          TextSpan(
                            text: token.text,
                            style: _style(token.kind, colors),
                          ),
                      ],
                    ),
                    style: mono,
                  ),
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

/// Zero width space: selectable but invisible, copied as nothing.
const String _emptyRowText = '\u200B';

class _RowSelectionDelegate extends StaticSelectionContainerDelegate {
  bool endsLine = false;
  bool empty = false;

  @override
  SelectedContent? getSelectedContent() {
    final content = super.getSelectedContent();
    if (content == null) return null;
    final text = empty ? '' : content.plainText;
    if (!endsLine) return SelectedContent(plainText: text);
    final range = getSelection();
    final reachesEnd =
        range != null &&
        math.max(range.startOffset, range.endOffset) >= contentLength;
    return SelectedContent(plainText: reachesEnd ? '$text\n' : text);
  }
}
