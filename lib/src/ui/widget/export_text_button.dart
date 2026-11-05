import 'package:flutter/material.dart';

import '../../feature/exporter.dart';
import '../../feature/text_export.dart';
import '../text/body_document.dart';

/// Copy button that turns into "Download .txt" for bodies over the copy limit.
class ExportTextButton extends StatelessWidget {
  const ExportTextButton({
    super.key,
    required this.copyLabel,
    required this.document,
    required this.fileName,
    required this.copiedTitle,
    this.limitBytes = kCopyLimitBytes,
  });

  final String copyLabel;
  final int limitBytes;
  final BodyDocument? document;
  final String fileName;
  final String copiedTitle;

  @override
  Widget build(BuildContext context) {
    final doc = document;
    if (doc == null) {
      return FilledButton.icon(
        icon: const Icon(Icons.copy),
        label: Text(copyLabel),
        onPressed: null,
      );
    }
    final download = exceedsCopyLimit(doc.byteLength, limitBytes: limitBytes);
    return FilledButton.icon(
      icon: Icon(download ? Icons.download : Icons.copy),
      label: Text(
        download
            ? 'Download .txt (${Exporter.formatSize(doc.byteLength)})'
            : copyLabel,
      ),
      onPressed: () => copyOrDownloadText(
        context,
        text: doc.text,
        fileName: fileName,
        copiedTitle: copiedTitle,
        limitBytes: limitBytes,
      ),
    );
  }
}
