import 'dart:convert';
import 'dart:typed_data';

import '../model/content_kind.dart';
import '../model/http_body.dart';

/// Binary bodies larger than this are recorded as metadata only (size +
/// content type) — the bytes are dropped rather than retained in memory,
/// since [SamseerHttpCall]s stay in memory for the life of the storage ring
/// buffer (up to `maxCallsCount` calls).
const int kSamseerMaxBinaryCapture = 2 * 1024 * 1024;

/// Decodes a captured request/response byte payload into the richest
/// representation its `Content-Type` supports:
/// - `application/json` (and `+json`) → parsed `Map`/`List`, falling back to
///   text if malformed.
/// - `application/x-www-form-urlencoded` → `Map<String, String>`.
/// - images, PDFs, `application/octet-stream` → [SamseerBinaryBody].
/// - anything else that is valid UTF-8 (`text/*`, XML, HTML, CSV, unknown
///   types) → the decoded [String], left for viewers/exporters to format.
/// - anything that fails to decode as UTF-8 → [SamseerBinaryBody], regardless
///   of the declared content type (a mislabeled binary payload is still
///   binary).
dynamic samseerDecodeBody(List<int> bytes, String? contentType) {
  final kind = classifyContentType(contentType);
  if (isBinaryBodyKind(kind)) {
    return _captureBinary(bytes, contentType);
  }
  final String text;
  try {
    text = utf8.decode(bytes);
  } catch (_) {
    return _captureBinary(bytes, contentType);
  }
  switch (kind) {
    case SamseerBodyKind.json:
      try {
        return json.decode(text);
      } catch (_) {
        return text;
      }
    case SamseerBodyKind.formUrlEncoded:
      try {
        return Uri.splitQueryString(text);
      } catch (_) {
        return text;
      }
    default:
      return text;
  }
}

SamseerBinaryBody _captureBinary(List<int> bytes, String? contentType) {
  if (bytes.length > kSamseerMaxBinaryCapture) {
    return SamseerBinaryBody(totalSize: bytes.length, contentType: contentType);
  }
  return SamseerBinaryBody(
    totalSize: bytes.length,
    bytes: Uint8List.fromList(bytes),
    contentType: contentType,
  );
}
