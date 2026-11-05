import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ui/widget/samseer_toast.dart';
import 'exporter.dart';

/// Bodies larger than this (UTF-8 bytes) are downloaded instead of copied.
const int kCopyLimitBytes = 100 * 1024;

bool exceedsCopyLimit(int utf8Bytes) => utf8Bytes > kCopyLimitBytes;

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

/// Saves bytes through a save dialog. True = saved, false = cancelled.
typedef TextFileSaver = Future<bool> Function(String fileName, Uint8List bytes);

class SamseerTextExport {
  SamseerTextExport._();

  /// Replaceable in tests.
  static TextFileSaver saver = _filePickerSaver;
}

Future<bool> _filePickerSaver(String fileName, Uint8List bytes) async {
  final uri = await FilePicker.saveFile(
    fileName: fileName,
    bytes: bytes,
    mimeType: 'text/plain',
  );
  return uri != null;
}

/// Copies [text] when small enough, otherwise saves it as a .txt file.
Future<void> copyOrDownloadText(
  BuildContext context, {
  required String text,
  required String fileName,
  required String copiedTitle,
}) async {
  final bytes = Uint8List.fromList(utf8.encode(text));
  if (!exceedsCopyLimit(bytes.length)) {
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
    final saved = await SamseerTextExport.saver(fileName, bytes);
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
