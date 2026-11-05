import 'dart:convert';

import 'package:dio/dio.dart';

import '../core/samseer_core.dart';
import '../model/http_body.dart';
import '../model/http_call.dart';
import '../model/http_error.dart';
import '../model/http_request.dart';
import '../model/http_response.dart';
import 'body_decoder.dart';

const String _kSamseerIdKey = '__samseer_id';

/// Dio [Interceptor] that records every request, response, and error to the
/// shared Samseer storage.
class SamseerDioInterceptor extends Interceptor {
  SamseerDioInterceptor(this._core);

  final SamseerCore _core;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final id = _core.nextId();
    options.extra[_kSamseerIdKey] = id;
    final body = _captureBody(options.data, options.contentType);
    final call = SamseerHttpCall(
      id: id,
      method: options.method.toUpperCase(),
      uri: options.uri.toString(),
      endpoint: options.uri.path.isEmpty ? '/' : options.uri.path,
      server: options.uri.host,
      secure: options.uri.scheme == 'https',
      client: 'Dio',
      createdAt: DateTime.now(),
      request: SamseerHttpRequest(
        time: DateTime.now(),
        headers: Map<String, dynamic>.from(options.headers),
        queryParameters: Map<String, dynamic>.from(options.queryParameters),
        body: body,
        contentType: options.contentType,
        size: _estimateSize(body),
      ),
    );
    _core.addCall(call);
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    final id = response.requestOptions.extra[_kSamseerIdKey] as int?;
    if (id != null) {
      final contentType = response.headers.value(Headers.contentTypeHeader);
      final body = _captureResponseBody(response.data, contentType);
      _core.addResponse(
        id,
        SamseerHttpResponse(
          status: response.statusCode ?? 0,
          time: DateTime.now(),
          headers: _flattenHeaders(response.headers.map),
          body: body,
          contentType: contentType,
          size: _estimateSize(body),
        ),
      );
    }
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final id = err.requestOptions.extra[_kSamseerIdKey] as int?;
    if (id != null) {
      final errResponse = err.response;
      if (errResponse != null) {
        final contentType = errResponse.headers.value(Headers.contentTypeHeader);
        final body = _captureResponseBody(errResponse.data, contentType);
        _core.addResponse(
          id,
          SamseerHttpResponse(
            status: errResponse.statusCode ?? 0,
            time: DateTime.now(),
            headers: _flattenHeaders(errResponse.headers.map),
            body: body,
            contentType: contentType,
            size: _estimateSize(body),
          ),
        );
      }
      _core.addError(
        id,
        SamseerHttpError(
          message: err.message,
          error: err.error,
          stackTrace: err.stackTrace,
        ),
      );
    }
    handler.next(err);
  }

  static Map<String, dynamic> _flattenHeaders(
      Map<String, List<String>> headers) {
    return headers.map((k, v) => MapEntry(k, v.length == 1 ? v.first : v));
  }

  /// Dio captures `options.data` as the raw value the caller passed — which
  /// may be a custom Dart class (with a `toJson()`) that Dio's transformer
  /// would normally serialize before sending. Without this round-trip, the
  /// inspector would display the object's `toString()` instead of the JSON
  /// actually sent on the wire.
  ///
  /// [FormData] (`multipart/form-data`) and raw byte bodies (`List<int>`,
  /// e.g. images/PDFs sent with an explicit content type) get their own
  /// richer representation instead of falling through to `toString()`.
  static dynamic _captureBody(dynamic data, String? contentType) {
    if (data == null) return null;
    if (data is String || data is num || data is bool) return data;
    if (data is FormData) {
      return SamseerMultipartBody(
        fields: {for (final e in data.fields) e.key: e.value},
        files: [
          for (final e in data.files)
            SamseerMultipartFilePart(
              field: e.key,
              filename: e.value.filename,
              contentType: e.value.contentType?.toString(),
              length: e.value.length,
            ),
        ],
      );
    }
    if (data is List<int>) return samseerDecodeBody(data, contentType);
    if (data is Map || data is List) return data;
    try {
      return json.decode(json.encode(data));
    } catch (_) {
      return data.toString();
    }
  }

  /// Dio's own [Transformer] already decodes text responses into
  /// `Map`/`List`/`String` per `ResponseType.json` (the default) — leave
  /// those alone. Only `ResponseType.bytes`/`stream` responses reach here as
  /// raw `List<int>`, in which case route them through the same
  /// content-type-aware decoder used by the other transports.
  static dynamic _captureResponseBody(dynamic data, String? contentType) {
    if (data is List<int>) return samseerDecodeBody(data, contentType);
    return data;
  }

  static int? _estimateSize(dynamic data) {
    if (data == null) return null;
    if (data is String) return data.length;
    if (data is List<int>) return data.length;
    if (data is SamseerBinaryBody) return data.totalSize;
    if (data is Map || data is List) {
      try {
        return data.toString().length;
      } catch (_) {
        return null;
      }
    }
    return null;
  }
}
