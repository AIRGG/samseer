import 'dart:convert';

import 'package:flutter/material.dart';

import '../theme/samseer_theme.dart';

/// Pretty, indented, syntax-highlighted JSON viewer. Falls back to a plain
/// monospace block for non-JSON values.
class JsonViewer extends StatelessWidget {
  const JsonViewer({super.key, required this.value});
  final dynamic value;

  @override
  Widget build(BuildContext context) {
    final dynamic decoded = _normalize(value);
    if (decoded is Map || decoded is List) {
      return _Tree(node: decoded);
    }
    return SelectableText(
      decoded?.toString() ?? '<empty>',
      style: SamseerTheme.mono(context),
    );
  }

  static dynamic _normalize(dynamic raw) {
    if (raw == null) return null;
    if (raw is String) {
      final trimmed = raw.trim();
      if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
        try {
          return json.decode(trimmed);
        } catch (_) {}
      }
      return raw;
    }
    return raw;
  }
}

class _Tree extends StatelessWidget {
  const _Tree({required this.node});
  final dynamic node;

  @override
  Widget build(BuildContext context) {
    return SelectableText.rich(
      TextSpan(children: _build(context, node, 0, isLast: true)),
      style: SamseerTheme.mono(context),
    );
  }

  List<InlineSpan> _build(
    BuildContext context,
    dynamic value,
    int depth, {
    required bool isLast,
  }) {
    final spans = <InlineSpan>[];
    final cs = Theme.of(context).colorScheme;
    final color = SamseerSyntaxColors(cs);
    if (value is Map) {
      spans.add(
        TextSpan(
          text: '{\n',
          style: TextStyle(color: color.bracket),
        ),
      );
      final entries = value.entries.toList();
      for (var i = 0; i < entries.length; i++) {
        final e = entries[i];
        final last = i == entries.length - 1;
        spans
          ..add(TextSpan(text: _indent(depth + 1)))
          ..add(
            TextSpan(
              text: '"${e.key}"',
              style: TextStyle(color: color.key, fontWeight: FontWeight.w600),
            ),
          )
          ..add(
            TextSpan(
              text: ': ',
              style: TextStyle(color: color.punct),
            ),
          )
          ..addAll(_build(context, e.value, depth + 1, isLast: last))
          ..add(TextSpan(text: last ? '\n' : ',\n'));
      }
      spans
        ..add(TextSpan(text: _indent(depth)))
        ..add(
          TextSpan(
            text: '}',
            style: TextStyle(color: color.bracket),
          ),
        );
    } else if (value is List) {
      spans.add(
        TextSpan(
          text: '[\n',
          style: TextStyle(color: color.bracket),
        ),
      );
      for (var i = 0; i < value.length; i++) {
        final last = i == value.length - 1;
        spans
          ..add(TextSpan(text: _indent(depth + 1)))
          ..addAll(_build(context, value[i], depth + 1, isLast: last))
          ..add(TextSpan(text: last ? '\n' : ',\n'));
      }
      spans
        ..add(TextSpan(text: _indent(depth)))
        ..add(
          TextSpan(
            text: ']',
            style: TextStyle(color: color.bracket),
          ),
        );
    } else if (value is String) {
      spans.add(
        TextSpan(
          text: '"${value.replaceAll('\n', '\\n')}"',
          style: TextStyle(color: color.string),
        ),
      );
    } else if (value is num) {
      spans.add(
        TextSpan(
          text: '$value',
          style: TextStyle(color: color.number),
        ),
      );
    } else if (value is bool) {
      spans.add(
        TextSpan(
          text: '$value',
          style: TextStyle(color: color.bool),
        ),
      );
    } else if (value == null) {
      spans.add(
        TextSpan(
          text: 'null',
          style: TextStyle(color: color.nullValue),
        ),
      );
    } else {
      spans.add(TextSpan(text: value.toString()));
    }
    return spans;
  }

  String _indent(int depth) => '  ' * depth;
}

/// JSON token colors shared by [JsonViewer] and the virtualized body view.
class SamseerSyntaxColors {
  SamseerSyntaxColors(ColorScheme cs)
    : key = cs.primary,
      string = const Color(0xFF22C55E),
      number = const Color(0xFFF59E0B),
      bool = const Color(0xFFEC4899),
      nullValue = cs.onSurfaceVariant,
      bracket = cs.onSurface,
      punct = cs.onSurfaceVariant;

  final Color key;
  final Color string;
  final Color number;
  final Color bool;
  final Color nullValue;
  final Color bracket;
  final Color punct;
}
