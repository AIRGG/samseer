import 'dart:convert';

import '../core/samseer_core.dart';
import '../model/console_log.dart';
import '../model/http_body.dart';
import '../model/http_call.dart';
import '../model/http_error.dart';
import '../model/http_request.dart';
import '../model/http_response.dart';
import '../interceptor/body_decoder.dart';

/// JavaScript snippet to inject into a WebView page (e.g. via
/// `flutter_inappwebview`'s `initialUserScripts` at document start).
///
/// Monkey-patches `XMLHttpRequest` and `fetch` to forward request, response,
/// and error events to the Dart side via the `samseer_webview` JavaScript
/// handler. Wire the handler to [Samseer.recordWebViewEvent] to surface the
/// captured calls inside the inspector.
///
/// Text bodies (JSON, form-urlencoded, XML, plain text, …) are forwarded as
/// plain strings. Binary responses (images, PDFs, `octet-stream`, …) are
/// read as bytes on the JS side and forwarded base64-encoded, tagged with
/// `bodyEncoding: 'base64'`, so the Dart side can decode them into the same
/// [SamseerBinaryBody] representation used by the other transports.
/// `FormData`/`URLSearchParams` request bodies are forwarded as a plain
/// field map tagged `bodyEncoding: 'form-fields'` (file parts are described,
/// not read, since that requires an async `FileReader` per file).
///
/// Re-installation is idempotent (guarded by `window.__samseer_installed`).
const String webViewInterceptorScript = r'''
(function () {
  if (window.__samseer_installed) return;
  window.__samseer_installed = true;

  var counter = 0;
  function nextCid() {
    counter += 1;
    return Date.now().toString() + ':' + counter.toString();
  }
  function send(payload) {
    try {
      if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
        var p = window.flutter_inappwebview.callHandler('samseer_webview', payload);
        // A rejected bridge call must not surface as an unhandledrejection,
        // which this script itself reports via send() (would loop forever).
        if (p && typeof p.catch === 'function') p.catch(function () {});
      }
    } catch (_) {}
  }
  function parseHeaders(raw) {
    var headers = {};
    if (!raw) return headers;
    raw.split('\r\n').forEach(function (line) {
      var idx = line.indexOf(':');
      if (idx > 0) {
        headers[line.substring(0, idx).trim().toLowerCase()] =
          line.substring(idx + 1).trim();
      }
    });
    return headers;
  }
  function isBinaryContentType(ct) {
    if (!ct) return false;
    ct = ct.toLowerCase();
    return ct.indexOf('image/') === 0 ||
      ct.indexOf('font/') === 0 ||
      ct.indexOf('video/') === 0 ||
      ct.indexOf('audio/') === 0 ||
      ct.indexOf('application/pdf') === 0 ||
      ct.indexOf('application/octet-stream') === 0;
  }
  function arrayBufferToBase64(buffer) {
    try {
      var bytes = new Uint8Array(buffer);
      var binary = '';
      var chunk = 0x8000;
      for (var i = 0; i < bytes.length; i += chunk) {
        binary += String.fromCharCode.apply(null, bytes.subarray(i, i + chunk));
      }
      return btoa(binary);
    } catch (_) {
      return null;
    }
  }
  // Returns { body, bodyEncoding? } describing a request body payload.
  function requestBodyPayload(body) {
    if (body == null) return { body: null };
    if (typeof body === 'string') return { body: body };
    if (typeof URLSearchParams !== 'undefined' && body instanceof URLSearchParams) {
      return { body: body.toString() };
    }
    if (typeof FormData !== 'undefined' && body instanceof FormData) {
      var fields = {};
      try {
        body.forEach(function (value, key) {
          if (typeof File !== 'undefined' && value instanceof File) {
            fields[key] = '<file: ' + value.name + ', ' + value.size + ' bytes>';
          } else {
            fields[key] = String(value);
          }
        });
      } catch (_) {}
      return { body: fields, bodyEncoding: 'form-fields' };
    }
    try {
      return { body: String(body) };
    } catch (_) {
      return { body: null };
    }
  }

  function safeStringify(value) {
    var seen = [];
    try {
      return JSON.stringify(value, function (key, val) {
        if (typeof val === 'function') {
          return '[Function: ' + (val.name || 'anonymous') + ']';
        }
        if (typeof val === 'object' && val !== null) {
          if (seen.indexOf(val) !== -1) return '[Circular]';
          seen.push(val);
        }
        return val;
      });
    } catch (e) {
      try { return String(value); } catch (_) { return '[Unserializable]'; }
    }
  }
  function describe(value) {
    if (value === null) return 'null';
    if (value === undefined) return 'undefined';
    var t = typeof value;
    if (t === 'string') return value;
    if (t === 'number' || t === 'boolean') return String(value);
    if (t === 'function') return '[Function: ' + (value.name || 'anonymous') + ']';
    if (value instanceof Error) {
      // message/stack are non-enumerable, JSON.stringify would give "{}".
      return (value.name || 'Error') + ': ' + value.message;
    }
    if (typeof Node !== 'undefined' && value instanceof Node) {
      var nid = value.id ? '#' + value.id : '';
      return '[' + (value.nodeName || 'Node') + nid + ']';
    }
    return safeStringify(value);
  }
  function formatArgs(args) {
    var parts = [];
    for (var i = 0; i < args.length; i++) parts.push(describe(args[i]));
    return parts.join(' ');
  }
  function collectData(args) {
    var data = [];
    for (var i = 0; i < args.length; i++) {
      var v = args[i];
      if (v !== null && typeof v === 'object' && !(v instanceof Error)) {
        try { data.push(JSON.parse(safeStringify(v))); }
        catch (_) { data.push(String(v)); }
      }
    }
    return data.length ? data : null;
  }
  function sendLog(level, args, stack) {
    send({
      kind: 'log',
      level: level,
      message: formatArgs(args),
      data: collectData(args),
      stack: stack || null,
    });
  }

  // --- console ---
  ['log', 'info', 'warn', 'error', 'debug'].forEach(function (level) {
    var orig = console[level];
    console[level] = function () {
      try {
        var stack = null;
        for (var i = 0; i < arguments.length; i++) {
          if (arguments[i] instanceof Error && arguments[i].stack) {
            stack = arguments[i].stack;
            break;
          }
        }
        sendLog(level, arguments, stack);
      } catch (_) {}
      if (orig) return orig.apply(console, arguments);
    };
  });

  // --- uncaught errors ---
  window.addEventListener('error', function (e) {
    var msg = (e && e.message) ? e.message : 'Uncaught error';
    var stack = (e && e.error && e.error.stack) ? e.error.stack : null;
    sendLog('error', [msg], stack);
  });
  window.addEventListener('unhandledrejection', function (e) {
    var reason = e && e.reason;
    var msg = describe(reason);
    var stack = (reason && reason.stack) ? reason.stack : null;
    sendLog('error', ['Unhandled rejection: ' + msg], stack);
  });

  // --- XMLHttpRequest ---
  var XHR = window.XMLHttpRequest;
  if (XHR) {
    function PatchedXHR() {
      var xhr = new XHR();
      var cid = nextCid();
      var meta = { method: 'GET', url: '', headers: {} };

      var origOpen = xhr.open;
      xhr.open = function (method, url) {
        meta.method = method;
        meta.url = url;
        return origOpen.apply(xhr, arguments);
      };
      var origSetHeader = xhr.setRequestHeader;
      xhr.setRequestHeader = function (k, v) {
        meta.headers[String(k).toLowerCase()] = String(v);
        return origSetHeader.apply(xhr, arguments);
      };
      var origSend = xhr.send;
      xhr.send = function (body) {
        var payload = requestBodyPayload(body);
        send({
          kind: 'req',
          cid: cid,
          method: meta.method,
          url: meta.url,
          headers: meta.headers,
          body: payload.body,
          bodyEncoding: payload.bodyEncoding,
        });
        return origSend.apply(xhr, arguments);
      };
      xhr.addEventListener('load', function () {
        var headers = parseHeaders(xhr.getAllResponseHeaders());
        var rt = xhr.responseType;
        if (rt === '' || rt === 'text') {
          send({ kind: 'res', cid: cid, status: xhr.status, headers: headers, body: xhr.responseText });
        } else if (rt === 'arraybuffer') {
          send({
            kind: 'res', cid: cid, status: xhr.status, headers: headers,
            body: arrayBufferToBase64(xhr.response), bodyEncoding: 'base64',
          });
        } else if (rt === 'blob' && xhr.response) {
          try {
            var reader = new FileReader();
            reader.onloadend = function () {
              var result = reader.result || '';
              var idx = result.indexOf(',');
              send({
                kind: 'res', cid: cid, status: xhr.status, headers: headers,
                body: idx >= 0 ? result.substring(idx + 1) : '', bodyEncoding: 'base64',
              });
            };
            reader.readAsDataURL(xhr.response);
          } catch (_) {
            send({ kind: 'res', cid: cid, status: xhr.status, headers: headers, body: null });
          }
        } else {
          send({ kind: 'res', cid: cid, status: xhr.status, headers: headers, body: null });
        }
      });
      xhr.addEventListener('error', function () {
        send({ kind: 'err', cid: cid, message: 'Network error' });
      });
      xhr.addEventListener('abort', function () {
        send({ kind: 'err', cid: cid, message: 'Aborted' });
      });
      xhr.addEventListener('timeout', function () {
        send({ kind: 'err', cid: cid, message: 'Timeout' });
      });
      return xhr;
    }
    PatchedXHR.prototype = XHR.prototype;
    window.XMLHttpRequest = PatchedXHR;
  }

  // --- fetch ---
  var origFetch = window.fetch;
  if (origFetch) {
    window.fetch = function (input, init) {
      var cid = nextCid();
      var url = typeof input === 'string'
        ? input
        : (input && input.url) || '';
      var method =
        (init && init.method) ||
        (input && typeof input !== 'string' && input.method) ||
        'GET';
      var headers = {};
      try {
        var h =
          (init && init.headers) ||
          (input && typeof input !== 'string' && input.headers);
        if (h) {
          if (typeof h.forEach === 'function') {
            h.forEach(function (v, k) {
              headers[String(k).toLowerCase()] = String(v);
            });
          } else if (Array.isArray(h)) {
            h.forEach(function (pair) {
              headers[String(pair[0]).toLowerCase()] = String(pair[1]);
            });
          } else {
            Object.keys(h).forEach(function (k) {
              headers[String(k).toLowerCase()] = String(h[k]);
            });
          }
        }
      } catch (_) {}
      var reqPayload = (init && init.body != null)
        ? requestBodyPayload(init.body)
        : { body: null };
      send({
        kind: 'req',
        cid: cid,
        method: method,
        url: url,
        headers: headers,
        body: reqPayload.body,
        bodyEncoding: reqPayload.bodyEncoding,
      });
      return origFetch.apply(this, arguments).then(function (res) {
        var resHeaders = {};
        try {
          res.headers.forEach(function (v, k) {
            resHeaders[String(k).toLowerCase()] = String(v);
          });
        } catch (_) {}
        if (isBinaryContentType(resHeaders['content-type'])) {
          res.clone().arrayBuffer().then(function (buf) {
            send({
              kind: 'res', cid: cid, status: res.status, headers: resHeaders,
              body: arrayBufferToBase64(buf), bodyEncoding: 'base64',
            });
          }).catch(function () {
            send({ kind: 'res', cid: cid, status: res.status, headers: resHeaders, body: null });
          });
        } else {
          res.clone().text().then(function (text) {
            send({ kind: 'res', cid: cid, status: res.status, headers: resHeaders, body: text });
          }).catch(function () {
            send({ kind: 'res', cid: cid, status: res.status, headers: resHeaders, body: null });
          });
        }
        return res;
      }).catch(function (err) {
        send({
          kind: 'err',
          cid: cid,
          message: String((err && err.message) || err),
        });
        throw err;
      });
    };
  }
})();
''';

/// Dispatches WebView events emitted by [webViewInterceptorScript] to
/// [SamseerCore]. Maintains a `cid → call id` mapping so requests and
/// responses captured separately on the JS side correlate to the same
/// inspector entry.
class SamseerWebViewDispatcher {
  SamseerWebViewDispatcher(this._core);

  final SamseerCore _core;
  final Map<String, int> _ids = <String, int>{};
  final Map<String, String> _urls = <String, String>{};

  void dispatch(Object? event) {
    if (event is! Map) return;
    final kind = event['kind'];
    if (kind is! String) return;
    if (kind == 'log') {
      _onLog(event);
      return;
    }
    final cid = event['cid'];
    if (cid is! String) return;
    switch (kind) {
      case 'req':
        _onRequest(cid, event);
        break;
      case 'res':
        _onResponse(cid, event);
        break;
      case 'err':
        _onError(cid, event);
        break;
    }
  }

  void _onRequest(String cid, Map event) {
    final method = (event['method'] ?? 'GET').toString().toUpperCase();
    final urlString = (event['url'] ?? '').toString();
    final uri = Uri.tryParse(urlString) ?? Uri();
    final headers = _toStringMap(event['headers']);
    final contentType = headers['content-type']?.toString();
    final body = _decodeEventBody(event, contentType);
    final id = _core.nextId();
    _ids[cid] = id;
    _urls[cid] = urlString;
    final now = DateTime.now();
    _core.addCall(SamseerHttpCall(
      id: id,
      method: method,
      uri: urlString,
      endpoint: uri.path.isEmpty ? '/' : uri.path,
      server: uri.host,
      secure: uri.scheme == 'https',
      client: 'WebView',
      createdAt: now,
      request: SamseerHttpRequest(
        time: now,
        headers: headers,
        queryParameters: Map<String, dynamic>.from(uri.queryParameters),
        body: body,
        contentType: contentType,
        size: _sizeOf(body),
      ),
    ));
  }

  void _onResponse(String cid, Map event) {
    final id = _ids.remove(cid);
    _urls.remove(cid);
    if (id == null) return;
    final status = event['status'];
    final headers = _toStringMap(event['headers']);
    final contentType = headers['content-type']?.toString();
    final body = _decodeEventBody(event, contentType);
    _core.addResponse(
      id,
      SamseerHttpResponse(
        status: status is int
            ? status
            : status is num
                ? status.toInt()
                : 0,
        time: DateTime.now(),
        headers: headers,
        body: body,
        contentType: contentType,
        size: _sizeOf(body),
      ),
    );
  }

  void _onError(String cid, Map event) {
    final id = _ids.remove(cid);
    final url = _urls.remove(cid);
    if (id == null) return;
    final message = event['message']?.toString();
    _core.addError(id, SamseerHttpError(message: message));
    if (_core.configuration.captureNetworkErrorsInConsole) {
      final where = url == null ? '' : ' ($url)';
      _core.addConsoleLog(SamseerConsoleLog(
        id: _core.nextId(),
        level: SamseerLogLevel.error,
        source: SamseerLogSource.webView,
        message: 'Network error$where: ${message ?? 'request failed'}',
        time: DateTime.now(),
      ));
    }
  }

  void _onLog(Map event) {
    final level = samseerLogLevelFromString(event['level']);
    final message = (event['message'] ?? '').toString();
    final rawData = event['data'];
    final List<Object?>? data = rawData is List
        ? rawData
        : (rawData == null ? null : <Object?>[rawData]);
    final stack = event['stack']?.toString();
    _core.addConsoleLog(SamseerConsoleLog(
      id: _core.nextId(),
      level: level,
      source: SamseerLogSource.webView,
      message: message,
      data: data,
      stackTrace: (stack == null || stack.isEmpty) ? null : stack,
      time: DateTime.now(),
    ));
  }

  static Map<String, dynamic> _toStringMap(Object? raw) {
    if (raw is Map) {
      return raw.map((k, v) => MapEntry(k.toString(), v));
    }
    return const <String, dynamic>{};
  }

  /// Decodes the raw `body`/`bodyEncoding` pair sent by the JS bridge:
  /// - `bodyEncoding: 'base64'` → binary bytes, run through the same
  ///   content-type-aware decoder used by the native transports (so an
  ///   `image/png` response becomes a [SamseerBinaryBody], JSON-typed bytes
  ///   get parsed, etc).
  /// - `bodyEncoding: 'form-fields'` → a captured `FormData`/URLSearchParams
  ///   field map, wrapped as [SamseerMultipartBody].
  /// - otherwise → a plain text body, decoded the same way (parses JSON,
  ///   form-urlencoded, …; left as a string for XML/HTML/CSV/plain text).
  static dynamic _decodeEventBody(Map event, String? contentType) {
    final raw = event['body'];
    if (raw == null) return null;
    final encoding = event['bodyEncoding'];
    if (encoding == 'base64' && raw is String) {
      try {
        return samseerDecodeBody(base64Decode(raw), contentType);
      } catch (_) {
        return null;
      }
    }
    if (encoding == 'form-fields' && raw is Map) {
      return SamseerMultipartBody(
        fields: raw.map((k, v) => MapEntry(k.toString(), v.toString())),
      );
    }
    if (raw is String) {
      return samseerDecodeBody(utf8.encode(raw), contentType);
    }
    return raw;
  }

  static int? _sizeOf(Object? body) {
    if (body == null) return null;
    if (body is String) return body.length;
    if (body is SamseerBinaryBody) return body.totalSize;
    return null;
  }
}
