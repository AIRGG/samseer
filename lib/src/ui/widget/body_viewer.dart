import 'package:flutter/material.dart';

import '../../model/content_kind.dart';
import '../../model/http_body.dart';
import 'binary_body_view.dart';
import 'csv_table.dart';
import 'json_viewer.dart';
import 'multipart_body_view.dart';
import 'xml_viewer.dart';

/// Routes a captured request/response body to whichever viewer fits its
/// shape/`Content-Type` best:
/// - [SamseerBinaryBody] (images, PDFs, `octet-stream`) → [BinaryBodyView]
/// - [SamseerMultipartBody] (`multipart/form-data`) → [MultipartBodyView]
/// - XML string → [XmlViewer]; CSV string → [CsvTable]
/// - everything else (JSON, form-urlencoded `Map`, plain text, HTML, …) →
///   [JsonViewer], which already renders `Map`/`List` as a tree and falls
///   back to plain selectable text.
class BodyViewer extends StatelessWidget {
  const BodyViewer({super.key, required this.body, this.contentType});
  final dynamic body;
  final String? contentType;

  @override
  Widget build(BuildContext context) {
    final value = body;
    if (value is SamseerBinaryBody) return BinaryBodyView(body: value);
    if (value is SamseerMultipartBody) return MultipartBodyView(body: value);
    if (value is String) {
      final kind = classifyContentType(contentType);
      if (kind == SamseerBodyKind.xml) return XmlViewer(value: value);
      if (kind == SamseerBodyKind.csv) return CsvTable(value: value);
    }
    return JsonViewer(value: value);
  }
}
