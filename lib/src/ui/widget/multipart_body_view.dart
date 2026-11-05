import 'package:flutter/material.dart';

import '../../model/http_body.dart';
import '../theme/samseer_theme.dart';
import 'key_value_table.dart';

/// Renders a `multipart/form-data` body: plain fields as a key/value table,
/// plus a list of file parts (filename, content type, size — the file
/// contents themselves are never captured).
class MultipartBodyView extends StatelessWidget {
  const MultipartBodyView({super.key, required this.body});
  final SamseerMultipartBody body;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (body.fields.isEmpty && body.files.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text('Empty multipart body',
            style: TextStyle(color: cs.onSurfaceVariant)),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (body.fields.isNotEmpty) KeyValueTable(entries: body.fields),
        if (body.files.isNotEmpty) ...[
          if (body.fields.isNotEmpty) const Divider(height: 1),
          for (final file in body.files) _FileRow(file: file),
        ],
      ],
    );
  }
}

class _FileRow extends StatelessWidget {
  const _FileRow({required this.file});
  final SamseerMultipartFilePart file;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.attach_file, size: 16, color: cs.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${file.field} = ${file.filename ?? '(no filename)'}',
                  style: SamseerTheme.mono(context, size: 12, weight: FontWeight.w600),
                ),
                if (file.contentType != null || file.length != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      [
                        if (file.contentType != null) file.contentType,
                        if (file.length != null) _fmtBytes(file.length!),
                      ].join(' · '),
                      style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _fmtBytes(int b) {
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
    return '${(b / 1024 / 1024).toStringAsFixed(2)} MB';
  }
}
