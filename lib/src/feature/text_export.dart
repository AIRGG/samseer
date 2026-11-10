import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/samseer_configuration.dart' show SamseerFileSaver;
import '../ui/widget/samseer_toast.dart';
import 'exporter.dart';

/// Default copy limit: text larger than this (UTF-8 bytes) is downloaded as a
/// .txt file instead of copied. Override with
/// `SamseerConfiguration.copyLimitBytes`.
const int kCopyLimitBytes = 100 * 1024;

/// Whether [utf8Bytes] is over [limitBytes] and should be downloaded.
bool exceedsCopyLimit(int utf8Bytes, {int limitBytes = kCopyLimitBytes}) =>
    utf8Bytes > limitBytes;

/// `samseer[-method][-endpoint]-part-yyyyMMdd-HHmmss.txt`
String buildExportFileName({
  required String part,
  String? method,
  String? endpoint,
  required DateTime time,
}) {
  String two(int v) => v.toString().padLeft(2, '0');
  final stamp =
      '${time.year.toString().padLeft(4, '0')}${two(time.month)}'
      '${two(time.day)}-${two(time.hour)}${two(time.minute)}${two(time.second)}';

  var slug = (endpoint ?? '')
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  if (slug.length > 40) {
    slug = slug.substring(0, 40).replaceAll(RegExp(r'-+$'), '');
  }

  final parts = <String>[
    'samseer',
    if (method != null && method.isNotEmpty) method.toLowerCase(),
    if (slug.isNotEmpty) slug,
    part,
    stamp,
  ];
  return '${parts.join('-')}.txt';
}

/// Replaced by `SamseerConfiguration.onSaveFile` when a [Samseer] is created
/// (and in tests). `null` means large text is copied like small text.
class SamseerTextExport {
  SamseerTextExport._();

  static SamseerFileSaver? saver;
}

/// Copies [text] when small enough or when no [SamseerTextExport.saver] is
/// set, otherwise saves it as a .txt file.
Future<void> copyOrDownloadText(
  BuildContext context, {
  required String text,
  required String fileName,
  required String copiedTitle,
  int limitBytes = kCopyLimitBytes,
}) async {
  final bytes = Uint8List.fromList(utf8.encode(text));
  final saver = SamseerTextExport.saver;
  if (saver == null ||
      !exceedsCopyLimit(bytes.length, limitBytes: limitBytes)) {
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    SamseerToast.show(
      context,
      copiedTitle,
      subtitle: Exporter.formatSize(bytes.length),
      variant: SamseerToastVariant.success,
    );
    return;
  }

  try {
    final saved = await saver(fileName, bytes);
    if (!saved || !context.mounted) return;
    SamseerToast.show(
      context,
      'Saved $fileName',
      variant: SamseerToastVariant.success,
    );
  } catch (e) {
    if (!context.mounted) return;
    SamseerToast.show(
      context,
      'Could not save file',
      subtitle: e.toString(),
      variant: SamseerToastVariant.error,
    );
  }
}
