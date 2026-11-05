import 'package:flutter/foundation.dart';

import 'http_body.dart';

@immutable
class SamseerHttpResponse {
  const SamseerHttpResponse({
    required this.status,
    required this.time,
    this.headers = const {},
    this.body,
    this.contentType,
    this.size,
  });

  final int status;
  final DateTime time;
  final Map<String, dynamic> headers;
  final dynamic body;
  final String? contentType;
  final int? size;

  Map<String, dynamic> toJson() => {
        'status': status,
        'time': time.toIso8601String(),
        'headers': headers,
        'body': _safeBody(body),
        'contentType': contentType,
        'size': size,
      };

  static dynamic _safeBody(dynamic body) {
    if (body == null) return null;
    if (body is String || body is num || body is bool) return body;
    if (body is List || body is Map) return body;
    if (body is SamseerBinaryBody) return body.toJson();
    if (body is SamseerMultipartBody) return body.toJson();
    return body.toString();
  }
}
