import 'dart:typed_data';

import 'package:flutter/material.dart';

/// Saves [bytes] as a file named [fileName]. Return `true` when saved, `false`
/// when the user cancelled.
typedef SamseerFileSaver = Future<bool> Function(
  String fileName,
  Uint8List bytes,
);

@immutable
class SamseerConfiguration {
  const SamseerConfiguration({
    this.maxCallsCount = 1000,
    this.showInspectorOnShake = true,
    this.showFloatingBubble = false,
    this.directionality,
    this.shakeThreshold = 20,
    this.maxConsoleLogsCount = 500,
    this.captureNetworkErrorsInConsole = true,
    this.copyLimitBytes = 100 * 1024,
    this.onSaveFile,
  }) : assert(copyLimitBytes >= 0);

  /// Max number of HTTP calls to keep in memory. Older calls are evicted FIFO.
  final int maxCallsCount;

  /// Whether shaking the device opens the inspector.
  final bool showInspectorOnShake;

  /// Whether to display a draggable floating bubble that opens the inspector.
  final bool showFloatingBubble;

  /// Force a text direction in the inspector. If null, uses the host app's.
  final TextDirection? directionality;

  /// Acceleration threshold (m/s^2) to trigger a shake event. Higher = harder
  /// shake required.
  final double shakeThreshold;

  /// Max number of console log entries to keep in memory. Older entries are
  /// evicted FIFO.
  final int maxConsoleLogsCount;

  /// Whether WebView/network errors are also surfaced as error-level entries
  /// in the Console. Successful (2xx/3xx) responses are never echoed.
  final bool captureNetworkErrorsInConsole;

  /// Copy limit in UTF-8 bytes. Copy actions (bodies, cURL, the call dump,
  /// "Copy as JSON", console entries) copy to the clipboard up to this size
  /// and offer "Download .txt" above it. `0` always downloads. Has no effect
  /// unless [onSaveFile] is set.
  final int copyLimitBytes;

  /// Saves large text as a file. Samseer ships no file dialog of its own, so
  /// the host app provides one (share sheet, file picker, ...). When `null`
  /// (default) every copy goes to the clipboard, whatever its size.
  final SamseerFileSaver? onSaveFile;

  /// [copyLimitBytes] when [onSaveFile] is set, otherwise unlimited.
  int get effectiveCopyLimitBytes =>
      onSaveFile == null ? 0x7fffffffffffffff : copyLimitBytes;

  SamseerConfiguration copyWith({
    int? maxCallsCount,
    bool? showInspectorOnShake,
    bool? showFloatingBubble,
    TextDirection? directionality,
    double? shakeThreshold,
    int? maxConsoleLogsCount,
    bool? captureNetworkErrorsInConsole,
    int? copyLimitBytes,
    SamseerFileSaver? onSaveFile,
  }) {
    return SamseerConfiguration(
      maxCallsCount: maxCallsCount ?? this.maxCallsCount,
      showInspectorOnShake: showInspectorOnShake ?? this.showInspectorOnShake,
      showFloatingBubble: showFloatingBubble ?? this.showFloatingBubble,
      directionality: directionality ?? this.directionality,
      shakeThreshold: shakeThreshold ?? this.shakeThreshold,
      maxConsoleLogsCount: maxConsoleLogsCount ?? this.maxConsoleLogsCount,
      captureNetworkErrorsInConsole:
          captureNetworkErrorsInConsole ?? this.captureNetworkErrorsInConsole,
      copyLimitBytes: copyLimitBytes ?? this.copyLimitBytes,
      onSaveFile: onSaveFile ?? this.onSaveFile,
    );
  }
}
