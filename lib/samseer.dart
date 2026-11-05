/// Samseer — beautiful HTTP inspector for Flutter.
///
/// Catches HTTP requests/responses from Dio, the `http` package, and
/// `dart:io` HttpClient and presents them in a Material 3 inspector UI.
library;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'src/core/samseer_configuration.dart';
import 'src/core/samseer_core.dart';
import 'src/feature/floating_bubble.dart';
import 'src/feature/webview_inspector.dart';
import 'src/interceptor/dio_interceptor.dart';
import 'src/interceptor/http_client.dart';
import 'src/interceptor/http_overrides.dart';
import 'src/model/http_call.dart';
import 'src/model/http_error.dart';
import 'src/model/http_request.dart';
import 'src/model/http_response.dart';

export 'src/core/samseer_configuration.dart';
export 'src/feature/floating_bubble.dart' show SamseerOverlay;
export 'src/feature/webview_inspector.dart' show webViewInterceptorScript;
export 'src/interceptor/dio_interceptor.dart' show SamseerDioInterceptor;
export 'src/interceptor/http_client.dart' show SamseerHttpClient;
export 'src/interceptor/http_overrides.dart' show SamseerHttpOverrides;
export 'src/model/content_kind.dart'
    show SamseerBodyKind, classifyContentType, isBinaryBodyKind;
export 'src/model/http_body.dart'
    show SamseerBinaryBody, SamseerMultipartBody, SamseerMultipartFilePart;
export 'src/model/http_call.dart' show SamseerHttpCall, SamseerCallState;
export 'src/model/http_error.dart' show SamseerHttpError;
export 'src/model/http_request.dart' show SamseerHttpRequest;
export 'src/model/http_response.dart' show SamseerHttpResponse;

/// Public entry point of the Samseer HTTP inspector.
///
/// ```dart
/// final samseer = Samseer();
///
/// MaterialApp(
///   navigatorKey: samseer.navigatorKey,
///   home: HomeScreen(),
/// );
///
/// // Dio
/// dio.interceptors.add(samseer.dioInterceptor);
///
/// // http package
/// final client = samseer.httpClient();
///
/// // dart:io HttpClient (global)
/// HttpOverrides.global = samseer.httpOverrides;
/// ```
class Samseer {
  Samseer({SamseerConfiguration configuration = const SamseerConfiguration()})
      : _core = SamseerCore(configuration: configuration);

  final SamseerCore _core;
  SamseerWebViewDispatcher? _webView;

  /// Configuration this instance was constructed with.
  SamseerConfiguration get configuration => _core.configuration;

  /// Attach this to your root [MaterialApp.navigatorKey] so Samseer can open
  /// the inspector from shake/floating-bubble triggers.
  GlobalKey<NavigatorState> get navigatorKey => _core.navigatorKey;

  /// Snapshot of all currently recorded calls (newest first).
  List<SamseerHttpCall> get calls => _core.storage.calls;

  /// Reactive stream of recorded calls.
  Stream<List<SamseerHttpCall>> get callsStream => _core.storage.stream;

  /// Dio interceptor — add to `dio.interceptors`.
  SamseerDioInterceptor get dioInterceptor => SamseerDioInterceptor(_core);

  /// Drop-in replacement for [http.Client] from the `http` package.
  /// Pass an [inner] client to delegate to (defaults to a new [http.Client]).
  SamseerHttpClient httpClient([http.Client? inner]) =>
      SamseerHttpClient(_core, inner);

  /// HttpOverrides for `dart:io` [HttpClient]. Install at startup:
  /// ```dart
  /// HttpOverrides.global = samseer.httpOverrides;
  /// ```
  SamseerHttpOverrides get httpOverrides => SamseerHttpOverrides(_core);

  /// Wrap your app's widget with [SamseerOverlay] to display a draggable
  /// floating bubble that opens the inspector on tap.
  Widget overlay({required Widget child}) =>
      SamseerOverlay(core: _core, child: child);

  /// Open the inspector. Requires [navigatorKey] is wired to MaterialApp.
  Future<void> showInspector() => _core.openInspector();

  /// Open the inspector against a known [BuildContext]. Useful in cases where
  /// you don't want to use the navigator key.
  Future<void> showInspectorFromContext(BuildContext context) =>
      _core.openInspectorFromContext(context);

  /// Clear all recorded calls.
  void clear() => _core.storage.clear();

  /// Manually record a request from a custom transport (WebView, GraphQL,
  /// gRPC, …). Returns the call id; pass it to [recordResponse] or
  /// [recordError] when the corresponding result arrives.
  int recordRequest({
    required String method,
    required String uri,
    required String client,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? queryParameters,
    Object? body,
    String? contentType,
    int? size,
  }) {
    final id = _core.nextId();
    final parsed = Uri.tryParse(uri) ?? Uri();
    final now = DateTime.now();
    final effectiveHeaders = headers ?? const <String, dynamic>{};
    _core.addCall(SamseerHttpCall(
      id: id,
      method: method.toUpperCase(),
      uri: uri,
      endpoint: parsed.path.isEmpty ? '/' : parsed.path,
      server: parsed.host,
      secure: parsed.scheme == 'https',
      client: client,
      createdAt: now,
      request: SamseerHttpRequest(
        time: now,
        headers: effectiveHeaders,
        queryParameters: queryParameters ??
            Map<String, dynamic>.from(parsed.queryParameters),
        body: body,
        contentType:
            contentType ?? effectiveHeaders['content-type']?.toString(),
        size: size,
      ),
    ));
    return id;
  }

  /// Attach a response to a previously recorded request (see [recordRequest]).
  void recordResponse(
    int id, {
    required int status,
    Map<String, dynamic>? headers,
    Object? body,
    String? contentType,
    int? size,
  }) {
    final effectiveHeaders = headers ?? const <String, dynamic>{};
    _core.addResponse(
      id,
      SamseerHttpResponse(
        status: status,
        time: DateTime.now(),
        headers: effectiveHeaders,
        body: body,
        contentType:
            contentType ?? effectiveHeaders['content-type']?.toString(),
        size: size,
      ),
    );
  }

  /// Attach an error to a previously recorded request (see [recordRequest]).
  void recordError(
    int id, {
    String? message,
    Object? error,
    StackTrace? stackTrace,
  }) {
    _core.addError(
      id,
      SamseerHttpError(message: message, error: error, stackTrace: stackTrace),
    );
  }

  /// Forward a single event payload from the [webViewInterceptorScript] JS
  /// bridge into the inspector. Wire this to the `samseer_webview` JavaScript
  /// handler in your WebView controller — see the README for setup.
  void recordWebViewEvent(Object? event) {
    (_webView ??= SamseerWebViewDispatcher(_core)).dispatch(event);
  }

  /// Free resources. Call when you no longer need this instance.
  void dispose() => _core.dispose();
}
