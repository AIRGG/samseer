import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../core/samseer_core.dart';
import '../model/http_call.dart';
import '../model/http_error.dart';
import '../model/http_request.dart';
import '../model/http_response.dart';
import 'body_decoder.dart';

/// [HttpOverrides] that intercepts every [HttpClient] created in the app and
/// records traffic to the shared Samseer storage.
///
/// Install once at startup:
/// ```dart
/// HttpOverrides.global = samseer.httpOverrides;
/// ```
class SamseerHttpOverrides extends HttpOverrides {
  SamseerHttpOverrides(this._core, [this._inner]);

  final SamseerCore _core;
  final HttpOverrides? _inner;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final HttpClient base = _inner != null
        ? _inner.createHttpClient(context)
        : super.createHttpClient(context);
    return _RecordingHttpClient(base, _core);
  }
}

class _RecordingHttpClient implements HttpClient {
  _RecordingHttpClient(this._inner, this._core);

  final HttpClient _inner;
  final SamseerCore _core;

  Future<HttpClientRequest> _wrap(
    Future<HttpClientRequest> Function() open,
    String method,
    Uri url,
  ) async {
    final id = _core.nextId();
    _core.addCall(SamseerHttpCall(
      id: id,
      method: method.toUpperCase(),
      uri: url.toString(),
      endpoint: url.path.isEmpty ? '/' : url.path,
      server: url.host,
      secure: url.scheme == 'https',
      client: 'HttpClient',
      createdAt: DateTime.now(),
      request: SamseerHttpRequest(
        time: DateTime.now(),
        queryParameters: Map<String, dynamic>.from(url.queryParameters),
      ),
    ));
    final inner = await open();
    return _RecordingHttpClientRequest(inner, _core, id);
  }

  @override
  Future<HttpClientRequest> open(
    String method,
    String host,
    int port,
    String path,
  ) =>
      _wrap(() => _inner.open(method, host, port, path), method,
          Uri(scheme: 'http', host: host, port: port, path: path));

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) =>
      _wrap(() => _inner.openUrl(method, url), method, url);

  @override
  Future<HttpClientRequest> get(String host, int port, String path) => _wrap(
      () => _inner.get(host, port, path),
      'GET',
      Uri(scheme: 'http', host: host, port: port, path: path));

  @override
  Future<HttpClientRequest> getUrl(Uri url) =>
      _wrap(() => _inner.getUrl(url), 'GET', url);

  @override
  Future<HttpClientRequest> post(String host, int port, String path) => _wrap(
      () => _inner.post(host, port, path),
      'POST',
      Uri(scheme: 'http', host: host, port: port, path: path));

  @override
  Future<HttpClientRequest> postUrl(Uri url) =>
      _wrap(() => _inner.postUrl(url), 'POST', url);

  @override
  Future<HttpClientRequest> put(String host, int port, String path) => _wrap(
      () => _inner.put(host, port, path),
      'PUT',
      Uri(scheme: 'http', host: host, port: port, path: path));

  @override
  Future<HttpClientRequest> putUrl(Uri url) =>
      _wrap(() => _inner.putUrl(url), 'PUT', url);

  @override
  Future<HttpClientRequest> delete(String host, int port, String path) => _wrap(
      () => _inner.delete(host, port, path),
      'DELETE',
      Uri(scheme: 'http', host: host, port: port, path: path));

  @override
  Future<HttpClientRequest> deleteUrl(Uri url) =>
      _wrap(() => _inner.deleteUrl(url), 'DELETE', url);

  @override
  Future<HttpClientRequest> head(String host, int port, String path) => _wrap(
      () => _inner.head(host, port, path),
      'HEAD',
      Uri(scheme: 'http', host: host, port: port, path: path));

  @override
  Future<HttpClientRequest> headUrl(Uri url) =>
      _wrap(() => _inner.headUrl(url), 'HEAD', url);

  @override
  Future<HttpClientRequest> patch(String host, int port, String path) => _wrap(
      () => _inner.patch(host, port, path),
      'PATCH',
      Uri(scheme: 'http', host: host, port: port, path: path));

  @override
  Future<HttpClientRequest> patchUrl(Uri url) =>
      _wrap(() => _inner.patchUrl(url), 'PATCH', url);

  // Pass-through configuration setters.

  @override
  bool get autoUncompress => _inner.autoUncompress;
  @override
  set autoUncompress(bool value) => _inner.autoUncompress = value;

  @override
  Duration? get connectionTimeout => _inner.connectionTimeout;
  @override
  set connectionTimeout(Duration? value) => _inner.connectionTimeout = value;

  @override
  Duration get idleTimeout => _inner.idleTimeout;
  @override
  set idleTimeout(Duration value) => _inner.idleTimeout = value;

  @override
  int? get maxConnectionsPerHost => _inner.maxConnectionsPerHost;
  @override
  set maxConnectionsPerHost(int? value) => _inner.maxConnectionsPerHost = value;

  @override
  String? get userAgent => _inner.userAgent;
  @override
  set userAgent(String? value) => _inner.userAgent = value;

  @override
  void addCredentials(
          Uri url, String realm, HttpClientCredentials credentials) =>
      _inner.addCredentials(url, realm, credentials);

  @override
  void addProxyCredentials(
    String host,
    int port,
    String realm,
    HttpClientCredentials credentials,
  ) =>
      _inner.addProxyCredentials(host, port, realm, credentials);

  @override
  set authenticate(
    Future<bool> Function(Uri url, String scheme, String? realm)? f,
  ) =>
      _inner.authenticate = f;

  @override
  set authenticateProxy(
    Future<bool> Function(String host, int port, String scheme, String? realm)?
        f,
  ) =>
      _inner.authenticateProxy = f;

  @override
  set badCertificateCallback(
    bool Function(X509Certificate cert, String host, int port)? callback,
  ) =>
      _inner.badCertificateCallback = callback;

  @override
  set connectionFactory(
    Future<ConnectionTask<Socket>> Function(
      Uri url,
      String? proxyHost,
      int? proxyPort,
    )? f,
  ) =>
      _inner.connectionFactory = f;

  @override
  set findProxy(String Function(Uri url)? f) => _inner.findProxy = f;

  @override
  set keyLog(Function(String line)? callback) => _inner.keyLog = callback;

  @override
  void close({bool force = false}) => _inner.close(force: force);
}

class _RecordingHttpClientRequest implements HttpClientRequest {
  _RecordingHttpClientRequest(this._inner, this._core, this._id);

  final HttpClientRequest _inner;
  final SamseerCore _core;
  final int _id;
  final List<int> _bodyBuffer = [];

  @override
  Future<HttpClientResponse> close() async {
    try {
      _recordRequest();
      final response = await _inner.close();
      final bytes = <int>[];
      final stream = response.transform<List<int>>(
        StreamTransformer<List<int>, List<int>>.fromHandlers(
          handleData: (data, sink) {
            bytes.addAll(data);
            sink.add(data);
          },
          handleDone: (sink) {
            final contentType = response.headers.contentType?.toString();
            final body = samseerDecodeBody(bytes, contentType);
            _core.addResponse(
              _id,
              SamseerHttpResponse(
                status: response.statusCode,
                time: DateTime.now(),
                headers: _readHeaders(response.headers),
                body: body,
                contentType: contentType,
                size: bytes.length,
              ),
            );
            sink.close();
          },
        ),
      );
      return _BufferedHttpClientResponse(response, stream);
    } catch (error, stack) {
      _core.addError(
        _id,
        SamseerHttpError(
            message: error.toString(), error: error, stackTrace: stack),
      );
      rethrow;
    }
  }

  /// [HttpClientRequest.headers] are only fully populated by the caller
  /// after [open]/[openUrl] returns (via `request.headers.add(...)`), and the
  /// body is streamed via [add]/[write] — so both are only knowable here, at
  /// [close] time. Patches the call recorded in [_wrap] with the real
  /// headers/body/content-type/size.
  void _recordRequest() {
    final existing = _core.storage.findById(_id);
    if (existing == null) return;
    final headers = _readHeaders(_inner.headers);
    final contentType = _inner.headers.contentType?.toString() ??
        headers['content-type']?.toString();
    final body =
        _bodyBuffer.isEmpty ? null : samseerDecodeBody(_bodyBuffer, contentType);
    _core.updateRequest(
      _id,
      existing.request.copyWith(
        headers: headers,
        body: body,
        contentType: contentType,
        size: _bodyBuffer.isEmpty ? null : _bodyBuffer.length,
      ),
    );
  }

  @override
  Future<HttpClientResponse> get done => _inner.done;

  @override
  void add(List<int> data) {
    _bodyBuffer.addAll(data);
    _inner.add(data);
  }

  @override
  void write(Object? object) {
    final s = object?.toString() ?? '';
    _bodyBuffer.addAll(utf8.encode(s));
    _inner.write(object);
  }

  @override
  void writeAll(Iterable<dynamic> objects, [String separator = '']) =>
      _inner.writeAll(objects, separator);

  @override
  void writeCharCode(int charCode) => _inner.writeCharCode(charCode);

  @override
  void writeln([Object? object = '']) => _inner.writeln(object);

  @override
  void addError(Object error, [StackTrace? stackTrace]) =>
      _inner.addError(error, stackTrace);

  @override
  Future<dynamic> addStream(Stream<List<int>> stream) =>
      _inner.addStream(stream);

  @override
  Future<dynamic> flush() => _inner.flush();

  @override
  bool get bufferOutput => _inner.bufferOutput;
  @override
  set bufferOutput(bool value) => _inner.bufferOutput = value;

  @override
  int get contentLength => _inner.contentLength;
  @override
  set contentLength(int value) => _inner.contentLength = value;

  @override
  Encoding get encoding => _inner.encoding;
  @override
  set encoding(Encoding value) => _inner.encoding = value;

  @override
  bool get followRedirects => _inner.followRedirects;
  @override
  set followRedirects(bool value) => _inner.followRedirects = value;

  @override
  int get maxRedirects => _inner.maxRedirects;
  @override
  set maxRedirects(int value) => _inner.maxRedirects = value;

  @override
  bool get persistentConnection => _inner.persistentConnection;
  @override
  set persistentConnection(bool value) => _inner.persistentConnection = value;

  @override
  HttpConnectionInfo? get connectionInfo => _inner.connectionInfo;

  @override
  List<Cookie> get cookies => _inner.cookies;

  @override
  HttpHeaders get headers => _inner.headers;

  @override
  String get method => _inner.method;

  @override
  Uri get uri => _inner.uri;

  @override
  void abort([Object? exception, StackTrace? stackTrace]) =>
      _inner.abort(exception, stackTrace);
}

class _BufferedHttpClientResponse extends StreamView<List<int>>
    implements HttpClientResponse {
  _BufferedHttpClientResponse(this._inner, Stream<List<int>> stream)
      : super(stream);

  final HttpClientResponse _inner;

  @override
  X509Certificate? get certificate => _inner.certificate;
  @override
  HttpClientResponseCompressionState get compressionState =>
      _inner.compressionState;
  @override
  HttpConnectionInfo? get connectionInfo => _inner.connectionInfo;
  @override
  int get contentLength => _inner.contentLength;
  @override
  List<Cookie> get cookies => _inner.cookies;
  @override
  Future<Socket> detachSocket() => _inner.detachSocket();
  @override
  HttpHeaders get headers => _inner.headers;
  @override
  bool get isRedirect => _inner.isRedirect;
  @override
  bool get persistentConnection => _inner.persistentConnection;
  @override
  String get reasonPhrase => _inner.reasonPhrase;
  @override
  Future<HttpClientResponse> redirect([
    String? method,
    Uri? url,
    bool? followLoops,
  ]) =>
      _inner.redirect(method, url, followLoops);
  @override
  List<RedirectInfo> get redirects => _inner.redirects;
  @override
  int get statusCode => _inner.statusCode;
}

Map<String, dynamic> _readHeaders(HttpHeaders headers) {
  final map = <String, dynamic>{};
  headers.forEach((name, values) {
    map[name] = values.length == 1 ? values.first : values;
  });
  return map;
}
