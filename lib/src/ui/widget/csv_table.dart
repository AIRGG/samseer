import 'package:flutter/material.dart';

import '../theme/samseer_theme.dart';

/// Minimal CSV grid — splits on newlines and commas with just enough
/// quote-awareness to keep quoted commas from breaking columns. Not a full
/// RFC 4180 parser; good enough for eyeballing a response body.
class CsvTable extends StatelessWidget {
  const CsvTable({super.key, required this.value});
  final String value;

  @override
  Widget build(BuildContext context) {
    final rows = _parse(value);
    if (rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'Empty CSV body',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      );
    }
    final cs = Theme.of(context).colorScheme;
    final columnCount = rows.map((r) => r.length).reduce((a, b) => a > b ? a : b);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.all(12),
      child: Table(
        border: TableBorder.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
        defaultColumnWidth: const IntrinsicColumnWidth(),
        children: [
          for (var r = 0; r < rows.length; r++)
            TableRow(
              decoration: r == 0
                  ? BoxDecoration(color: cs.surfaceContainerHighest)
                  : null,
              children: [
                for (var c = 0; c < columnCount; c++)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    child: Text(
                      c < rows[r].length ? rows[r][c] : '',
                      style: SamseerTheme.mono(
                        context,
                        size: 12,
                        weight: r == 0 ? FontWeight.w700 : FontWeight.w400,
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  static List<List<String>> _parse(String input) {
    final lines = input.split(RegExp(r'\r\n|\n|\r')).where((l) => l.isNotEmpty);
    return [for (final line in lines) _parseLine(line)];
  }

  static List<String> _parseLine(String line) {
    final fields = <String>[];
    final buffer = StringBuffer();
    var inQuotes = false;
    for (var i = 0; i < line.length; i++) {
      final ch = line[i];
      if (ch == '"') {
        if (inQuotes && i + 1 < line.length && line[i + 1] == '"') {
          buffer.write('"');
          i++;
        } else {
          inQuotes = !inQuotes;
        }
      } else if (ch == ',' && !inQuotes) {
        fields.add(buffer.toString());
        buffer.clear();
      } else {
        buffer.write(ch);
      }
    }
    fields.add(buffer.toString());
    return fields;
  }
}
