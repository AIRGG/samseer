import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../feature/exporter.dart';
import '../../model/content_kind.dart';
import '../../model/http_body.dart';
import 'body_rows.dart';

/// The exact text Copy/Download produces plus its numbered rows.
class BodyDocument {
  const BodyDocument({
    required this.text,
    required this.rows,
    required this.byteLength,
  });

  final String text;
  final List<BodyRow> rows;
  final int byteLength;

  /// Number of source lines (continuation rows are not counted).
  int get lineCount => rows.where((r) => r.lineNumber != null).length;
}

BodyDocument documentFromText(String text, {required bool highlightJson}) {
  return BodyDocument(
    text: text,
    rows: buildRows(text, highlightJson: highlightJson),
    byteLength: utf8.encode(text).length,
  );
}

BodyDocument documentFromBody(dynamic body, {String? contentType}) {
  final text = Exporter.formatBody(body, contentType: contentType);
  final trimmed = text.trim();
  return documentFromText(
    text,
    highlightJson: trimmed.startsWith('{') || trimmed.startsWith('['),
  );
}

/// Whether the body goes through the virtualized text viewer.
bool usesTextViewer(dynamic body, String? contentType) {
  if (body is SamseerBinaryBody || body is SamseerMultipartBody) return false;
  if (body is String &&
      classifyContentType(contentType) == SamseerBodyKind.csv) {
    return false;
  }
  return true;
}

final Expando<Map<String, Future<BodyDocument>>> _documentCache =
    Expando<Map<String, Future<BodyDocument>>>('samseerBodyDocument');

/// Builds a document off the UI thread, cached per [owner] and [slot] so
/// rebuilds never redo the work.
Future<BodyDocument> loadBodyDocument(
  Object owner,
  String slot,
  BodyDocument Function() build,
) {
  final slots = _documentCache[owner] ??= <String, Future<BodyDocument>>{};
  return slots[slot] ??= compute((_) => build(), null);
}
