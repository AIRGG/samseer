import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:samseer/samseer.dart';

/// Demo page showing how to wire `webViewInterceptorScript` and the
/// `samseer_webview` JavaScript handler into `flutter_inappwebview`.
///
/// Loads a small self-contained HTML page with buttons that explicitly fire
/// `fetch` and `XMLHttpRequest` calls — the interceptor only captures those
/// two APIs, so a regular form-submit on a real site would *not* show up.
class SamseerWebViewDemoPage extends StatefulWidget {
  const SamseerWebViewDemoPage({super.key, required this.samseer});

  final Samseer samseer;

  @override
  State<SamseerWebViewDemoPage> createState() => _SamseerWebViewDemoPageState();
}

class _SamseerWebViewDemoPageState extends State<SamseerWebViewDemoPage> {
  InAppWebViewController? _controller;

  static const String _demoHtml = r'''
<!doctype html>
<html>
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width,initial-scale=1" />
  <title>Samseer WebView Demo</title>
  <style>
    body { font-family: -apple-system, system-ui, sans-serif; margin: 0; padding: 16px; background: #fafafa; }
    h2 { margin: 0 0 8px; font-size: 18px; }
    p { margin: 0 0 16px; color: #555; font-size: 13px; }
    button { display: block; width: 100%; padding: 14px; margin: 6px 0;
             font-size: 14px; border-radius: 10px; border: 1px solid #d0d0d0;
             background: #fff; text-align: left; }
    button:active { background: #eee; }
    pre { background: #1f1f1f; color: #c8e6c9; padding: 12px; border-radius: 10px;
          font-size: 12px; max-height: 220px; overflow: auto; margin-top: 16px; }
  </style>
</head>
<body>
  <h2>Samseer WebView Demo</h2>
  <p>Tap a button below — calls show up in the Samseer inspector with <code>client = WebView</code>.</p>

  <button onclick="doFetchGet()">fetch GET /todos/1</button>
  <button onclick="doFetchPost()">fetch POST /posts</button>
  <button onclick="doXhrGet()">XHR GET /users/1</button>
  <button onclick="doFetch404()">fetch GET 404 (error)</button>
  <button onclick="console.log('plain log from webview')">console.log string</button>
  <button onclick="console.warn('heads up')">console.warn</button>
  <button onclick="console.error('something broke')">console.error</button>
  <button onclick="logObject()">console.log object + array</button>
  <button onclick="console.log('mixed', 42, true, {k:'v'})">console.log mixed args</button>
  <button onclick="boom()">throw uncaught error</button>
  <button onclick="rejectPromise()">unhandled promise rejection</button>
  <button onclick="doFetchFail()">fetch unreachable host (network error)</button>

  <pre id="log">// output will appear here</pre>

  <script>
    function log(line) {
      var el = document.getElementById('log');
      el.textContent = line + '\n' + el.textContent;
    }
    async function doFetchGet() {
      try {
        var r = await fetch('https://jsonplaceholder.typicode.com/todos/1');
        var j = await r.json();
        log('fetch GET → ' + r.status + ' ' + JSON.stringify(j));
      } catch (e) { log('fetch GET error → ' + e); }
    }
    async function doFetchPost() {
      try {
        var r = await fetch('https://jsonplaceholder.typicode.com/posts', {
          method: 'POST',
          headers: { 'content-type': 'application/json' },
          body: JSON.stringify({ title: 'hello', body: 'samseer', userId: 1 }),
        });
        var j = await r.json();
        log('fetch POST → ' + r.status + ' ' + JSON.stringify(j));
      } catch (e) { log('fetch POST error → ' + e); }
    }
    function doXhrGet() {
      var x = new XMLHttpRequest();
      x.open('GET', 'https://jsonplaceholder.typicode.com/users/1');
      x.setRequestHeader('x-demo', 'samseer');
      x.onload = function () { log('XHR → ' + x.status + ' ' + x.responseText.slice(0, 80)); };
      x.onerror = function () { log('XHR error'); };
      x.send();
    }
    async function doFetch404() {
      var r = await fetch('https://jsonplaceholder.typicode.com/notfound');
      log('fetch 404 → ' + r.status);
    }
    function logObject() {
      console.log('an object:', { id: 1, tags: ['a', 'b'], ok: true }, [10, 20, 30]);
    }
    function boom() {
      throw new Error('deliberate webview error');
    }
    function rejectPromise() {
      Promise.reject(new Error('deliberate rejection'));
    }
    async function doFetchFail() {
      try {
        await fetch('https://samseer-demo.invalid/ping');
      } catch (e) {
        log('fetch failed → ' + e.message);
      }
    }
  </script>
</body>
</html>
''';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('WebView demo'),
        actions: [
          IconButton(
            icon: const Icon(Icons.bug_report_outlined),
            tooltip: 'Open inspector',
            onPressed: widget.samseer.showInspector,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Reload',
            onPressed: () => _controller?.reload(),
          ),
        ],
      ),
      body: InAppWebView(
        initialData: InAppWebViewInitialData(
          data: _demoHtml,
          baseUrl: WebUri('https://samseer.local/'),
        ),
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
        ),
        initialUserScripts: UnmodifiableListView<UserScript>([
          UserScript(
            source: webViewInterceptorScript,
            injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
          ),
        ]),
        onWebViewCreated: (controller) {
          _controller = controller;
          controller.addJavaScriptHandler(
            handlerName: 'samseer_webview',
            callback: (args) {
              if (args.isNotEmpty) {
                widget.samseer.recordWebViewEvent(args.first);
              }
            },
          );
        },
      ),
    );
  }
}
