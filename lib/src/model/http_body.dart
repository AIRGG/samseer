import 'package:flutter/foundation.dart';

/// A body captured as raw bytes rather than text — used for images, PDFs,
/// and any other `application/octet-stream`-like payload.
///
/// [bytes] is null when the payload exceeded [kSamseerMaxBinaryCapture]: the
/// size and content type are still known (from headers), but the bytes
/// themselves were not retained in memory.
@immutable
class SamseerBinaryBody {
  const SamseerBinaryBody({
    required this.totalSize,
    this.bytes,
    this.contentType,
  });

  final int totalSize;
  final Uint8List? bytes;
  final String? contentType;

  bool get truncated => bytes == null;

  Map<String, dynamic> toJson() => {
        'kind': 'binary',
        'contentType': contentType,
        'size': totalSize,
        'truncated': truncated,
      };

  @override
  String toString() =>
      '<binary body: $totalSize bytes${contentType != null ? ', $contentType' : ''}>';
}

/// Metadata for a single file part of a `multipart/form-data` body. File
/// contents are never captured — only enough to describe what was sent.
@immutable
class SamseerMultipartFilePart {
  const SamseerMultipartFilePart({
    required this.field,
    this.filename,
    this.contentType,
    this.length,
  });

  final String field;
  final String? filename;
  final String? contentType;
  final int? length;

  Map<String, dynamic> toJson() => {
        'field': field,
        'filename': filename,
        'contentType': contentType,
        'length': length,
      };
}

/// A `multipart/form-data` body: plain fields plus metadata about any file
/// parts (filename/content-type/size — never the file bytes themselves).
@immutable
class SamseerMultipartBody {
  const SamseerMultipartBody({
    this.fields = const <String, String>{},
    this.files = const <SamseerMultipartFilePart>[],
  });

  final Map<String, String> fields;
  final List<SamseerMultipartFilePart> files;

  Map<String, dynamic> toJson() => {
        'kind': 'multipart',
        'fields': fields,
        'files': files.map((f) => f.toJson()).toList(),
      };

  @override
  String toString() =>
      'multipart: ${fields.length} field(s), ${files.length} file(s)';
}
