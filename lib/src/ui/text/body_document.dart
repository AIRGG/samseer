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
  final BodyRows rows;
  final int byteLength;

  /// Number of source lines (continuation rows are not counted).
  int get lineCount => rows.lineCount;
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

/// How many documents stay cached. Each one holds its full text, so the cap
/// keeps several multi-megabyte bodies from piling up in memory.
const int kBodyDocumentCacheSize = 5;

class _CacheEntry {
  _CacheEntry(this.owner, this.slot, this.future);
  final Object owner;
  final String slot;
  final Future<BodyDocument> future;
}

/// Least recently used first.
final List<_CacheEntry> _documentCache = <_CacheEntry>[];

/// Builds a document off the UI thread, cached per [owner] and [slot] so
/// rebuilds never redo the work. Only the [kBodyDocumentCacheSize] most
/// recently used documents are kept.
Future<BodyDocument> loadBodyDocument(
  Object owner,
  String slot,
  BodyDocument Function() build,
) {
  for (var i = 0; i < _documentCache.length; i++) {
    final entry = _documentCache[i];
    if (identical(entry.owner, owner) && entry.slot == slot) {
      if (i != _documentCache.length - 1) {
        _documentCache
          ..removeAt(i)
          ..add(entry);
      }
      return entry.future;
    }
  }
  final future = compute((_) => build(), null);
  _documentCache.add(_CacheEntry(owner, slot, future));
  if (_documentCache.length > kBodyDocumentCacheSize) {
    _documentCache.removeAt(0);
  }
  return future;
}
