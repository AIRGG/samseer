import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../model/content_kind.dart';
import '../../model/http_body.dart';
import '../theme/samseer_theme.dart';
import 'samseer_toast.dart';

/// Renders a [SamseerBinaryBody] — an image preview when the content type is
/// `image/*`, otherwise a generic file card (PDF, `octet-stream`, …). Always
/// offers a "Copy as Base64" action when the bytes were actually retained
/// (see [SamseerBinaryBody.truncated]).
class BinaryBodyView extends StatelessWidget {
  const BinaryBodyView({super.key, required this.body});
  final SamseerBinaryBody body;

  @override
  Widget build(BuildContext context) {
    final kind = classifyContentType(body.contentType);
    final cs = Theme.of(context).colorScheme;
    final bytes = body.bytes;

    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (kind == SamseerBodyKind.image && bytes != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Container(
                color: cs.surfaceContainerHighest,
                alignment: Alignment.center,
                constraints: const BoxConstraints(maxHeight: 320),
                child: Image.memory(bytes, fit: BoxFit.contain),
              ),
            )
          else
            _FileCard(kind: kind, body: body),
          const SizedBox(height: 10),
          Text(
            _caption(),
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
          ),
          if (bytes != null) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              icon: const Icon(Icons.copy, size: 16),
              label: const Text('Copy as Base64'),
              onPressed: () => _copyBase64(context, bytes),
            ),
          ],
        ],
      ),
    );
  }

  String _caption() {
    final type = body.contentType ?? 'unknown type';
    final size = _fmtBytes(body.totalSize);
    if (body.truncated) {
      return '$type · $size · not retained in memory (too large to preview or copy)';
    }
    return '$type · $size';
  }

  Future<void> _copyBase64(BuildContext context, List<int> bytes) async {
    final encoded = base64Encode(bytes);
    await Clipboard.setData(ClipboardData(text: encoded));
    if (!context.mounted) return;
    final large = encoded.length > 1024 * 1024;
    SamseerToast.show(
      context,
      large ? 'Copied — large content (${_fmtBytes(encoded.length)})' : 'Copied as Base64',
      subtitle: large ? 'Some apps may truncate.' : _fmtBytes(bytes.length),
      variant: large ? SamseerToastVariant.warning : SamseerToastVariant.success,
    );
  }

  static String _fmtBytes(int b) {
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
    return '${(b / 1024 / 1024).toStringAsFixed(2)} MB';
  }
}

class _FileCard extends StatelessWidget {
  const _FileCard({required this.kind, required this.body});
  final SamseerBodyKind kind;
  final SamseerBinaryBody body;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(_iconFor(kind), color: cs.primary, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              kind == SamseerBodyKind.pdf ? 'PDF document' : 'Binary payload',
              style: SamseerTheme.mono(context, weight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  IconData _iconFor(SamseerBodyKind kind) {
    switch (kind) {
      case SamseerBodyKind.pdf:
        return Icons.picture_as_pdf_outlined;
      case SamseerBodyKind.image:
        return Icons.image_outlined;
      default:
        return Icons.insert_drive_file_outlined;
    }
  }
}
