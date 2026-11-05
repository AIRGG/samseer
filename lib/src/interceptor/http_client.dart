import 'dart:async';

import 'package:http/http.dart' as http;

import '../core/samseer_core.dart';
import '../model/http_body.dart';
import '../model/http_call.dart';
import '../model/http_error.dart';
import '../model/http_request.dart';
import '../model/http_response.dart';
import 'body_decoder.dart';

/// A drop-in replacement for [http.Client] that records every request to the
/// shared Samseer storage.
///
/// Wraps an inner client (defaults to [http.Client.new]).
class SamseerHttpClient extends http.BaseClient {
  SamseerHttpClient(this._core, [http.Client? inner])
      : _inner = inner ?? http.Client();

  final SamseerCore _core;
  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final id = _core.nextId();
    final uri = request.url;
    final contentType = request.headers['content-type'];
    final body = _captureBody(request);
    final call = SamseerHttpCall(
      id: id,
      method: request.method.toUpperCase(),
      uri: uri.toString(),
      endpoint: uri.path.isEmpty ? '/' : uri.path,
      server: uri.host,
      secure: uri.scheme == 'https',
      client: 'http',
      createdAt: DateTime.now(),
      request: SamseerHttpRequest(
        time: DateTime.now(),
        headers: Map<String, dynamic>.from(request.headers),
        queryParameters: Map<String, dynamic>.from(uri.queryParameters),
        body: body,
        contentType: contentType,
        size: request.contentLength,
      ),
    );
    _core.addCall(call);

    try {
      final response = await _inner.send(request);
      // Buffer the stream so we can both record it and return it to the caller.
      final bytes = await response.stream.toBytes();
      final decoded =
          samseerDecodeBody(bytes, response.headers['content-type']);
      _core.addResponse(
        id,
        SamseerHttpResponse(
          status: response.statusCode,
          time: DateTime.now(),
          headers: Map<String, dynamic>.from(response.headers),
          body: decoded,
          contentType: response.headers['content-type'],
          size: bytes.length,
        ),
      );
      return http.StreamedResponse(
        Stream<List<int>>.value(bytes),
        response.statusCode,
        contentLength: bytes.length,
        request: response.request,
        headers: response.headers,
        isRedirect: response.isRedirect,
        persistentConnection: response.persistentConnection,
        reasonPhrase: response.reasonPhrase,
      );
    } catch (error, stack) {
      _core.addError(
        id,
        SamseerHttpError(
          message: error.toString(),
          error: error,
          stackTrace: stack,
        ),
      );
      rethrow;
    }
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }

  dynamic _captureBody(http.BaseRequest request) {
    if (request is http.Request) {
      return samseerDecodeBody(
          request.bodyBytes, request.headers['content-type']);
    }
    if (request is http.MultipartRequest) {
      return SamseerMultipartBody(
        fields: Map<String, String>.from(request.fields),
        files: [
          for (final f in request.files)
            SamseerMultipartFilePart(
              field: f.field,
              filename: f.filename,
              contentType: f.contentType.toString(),
              length: f.length,
            ),
        ],
      );
    }
    return null;
  }
}
