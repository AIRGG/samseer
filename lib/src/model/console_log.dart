import 'package:flutter/foundation.dart';

/// Severity of a captured console entry.
enum SamseerLogLevel { log, info, warn, error, debug }

/// Origin of a captured console entry.
enum SamseerLogSource { app, webView }

/// A single captured log line from the Flutter app or a WebView.
@immutable
class SamseerConsoleLog {
  const SamseerConsoleLog({
    required this.id,
    required this.level,
    required this.source,
    required this.message,
    required this.time,
    this.data,
    this.stackTrace,
  });

  final int id;
  final SamseerLogLevel level;
  final SamseerLogSource source;

  /// Already-formatted, readable message text.
  final String message;

  /// Structured arguments (objects/arrays) for pretty-printing in the detail
  /// view. Null when the entry carried no structured data.
  final List<Object?>? data;

  /// Stack trace for error-level entries, when available.
  final String? stackTrace;

  final DateTime time;

  Map<String, dynamic> toJson() => {
        'id': id,
        'level': level.name,
        'source': source.name,
        'message': message,
        'data': data,
        'stackTrace': stackTrace,
        'time': time.toIso8601String(),
      };
}

/// Maps a JS console level string to [SamseerLogLevel]. Unknown values
/// (including null) fall back to [SamseerLogLevel.log].
SamseerLogLevel samseerLogLevelFromString(Object? raw) {
  switch (raw?.toString()) {
    case 'info':
      return SamseerLogLevel.info;
    case 'warn':
    case 'warning':
      return SamseerLogLevel.warn;
    case 'error':
      return SamseerLogLevel.error;
    case 'debug':
      return SamseerLogLevel.debug;
    default:
      return SamseerLogLevel.log;
  }
}
