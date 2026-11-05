/// Coarse classification of a body's shape, derived from its `Content-Type`.
///
/// Drives which decoder and which viewer/exporter branch a body goes through.
enum SamseerBodyKind {
  json,
  formUrlEncoded,
  multipart,
  xml,
  html,
  csv,
  text,
  image,
  pdf,
  binary,
  unknown,
}

/// Classifies a raw `Content-Type` header value (with or without a
/// `; charset=...` suffix) into a [SamseerBodyKind].
SamseerBodyKind classifyContentType(String? contentType) {
  if (contentType == null) return SamseerBodyKind.unknown;
  final mime = contentType.split(';').first.trim().toLowerCase();
  if (mime.isEmpty) return SamseerBodyKind.unknown;
  if (mime == 'application/json' || mime.endsWith('+json')) {
    return SamseerBodyKind.json;
  }
  if (mime == 'application/x-www-form-urlencoded') {
    return SamseerBodyKind.formUrlEncoded;
  }
  if (mime.startsWith('multipart/')) return SamseerBodyKind.multipart;
  if (mime == 'application/pdf') return SamseerBodyKind.pdf;
  if (mime.startsWith('image/')) return SamseerBodyKind.image;
  if (mime == 'application/xml' ||
      mime == 'text/xml' ||
      mime.endsWith('+xml')) {
    return SamseerBodyKind.xml;
  }
  if (mime == 'text/html') return SamseerBodyKind.html;
  if (mime == 'text/csv') return SamseerBodyKind.csv;
  if (mime.startsWith('text/')) return SamseerBodyKind.text;
  if (mime == 'application/octet-stream') return SamseerBodyKind.binary;
  return SamseerBodyKind.unknown;
}

/// True for kinds whose payload is retained as raw bytes rather than text.
bool isBinaryBodyKind(SamseerBodyKind kind) =>
    kind == SamseerBodyKind.image ||
    kind == SamseerBodyKind.pdf ||
    kind == SamseerBodyKind.binary;
