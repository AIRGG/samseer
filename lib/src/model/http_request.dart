import 'package:flutter/foundation.dart';

import 'http_body.dart';

@immutable
class SamseerHttpRequest {
  const SamseerHttpRequest({
    required this.time,
    this.headers = const {},
    this.queryParameters = const {},
    this.body,
    this.contentType,
    this.size,
  });

  final DateTime time;
  final Map<String, dynamic> headers;
  final Map<String, dynamic> queryParameters;
  final dynamic body;
  final String? contentType;
  final int? size;

  SamseerHttpRequest copyWith({
    Map<String, dynamic>? headers,
    Map<String, dynamic>? queryParameters,
    dynamic body,
    String? contentType,
    int? size,
  }) {
    return SamseerHttpRequest(
      time: time,
      headers: headers ?? this.headers,
      queryParameters: queryParameters ?? this.queryParameters,
      body: body ?? this.body,
      contentType: contentType ?? this.contentType,
      size: size ?? this.size,
    );
  }

  Map<String, dynamic> toJson() => {
        'time': time.toIso8601String(),
        'headers': headers,
        'queryParameters': queryParameters,
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
