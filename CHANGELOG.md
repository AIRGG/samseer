## 0.5.0

* New: full content-type-aware body handling across every transport (Dio,
  `http`, `dart:io HttpClient`, WebView) — `application/json`,
  `multipart/form-data`, `application/x-www-form-urlencoded`, `text/plain`,
  `text/html`, `application/xml`, `application/octet-stream`,
  `application/pdf`, `text/csv`, and `image/*` are all classified, decoded,
  and rendered appropriately instead of falling back to raw text or a
  `<N bytes>` placeholder
* New: body viewer now routes each body to the right widget — image
  preview, file card (PDF/octet-stream) with a **Copy as Base64** action,
  multipart fields/files table, pretty-printed XML, CSV grid, or the
  existing JSON tree/plain-text viewer
* New: `SamseerBinaryBody` and `SamseerMultipartBody` model types (exported)
  represent binary and multipart bodies; binary bytes are capped at 2 MB in
  memory per body — beyond that only size/content-type metadata is kept
* New: `Exporter`/cURL output is content-type aware — form-urlencoded
  `Map`s are encoded as `key=value&...`, multipart bodies become `-F`
  flags, binary bodies are described in a comment instead of embedded
  inline
* Fix: `SamseerHttpOverrides` (`dart:io` `HttpClient`) previously never
  recorded request headers or body at all — both are now captured at
  request-close time
* Fix: the WebView inspector script now reads binary responses (images,
  PDFs, `octet-stream`) as bytes via `arraybuffer`/`blob` instead of
  corrupting them through `.text()`, and captures `FormData`/
  `URLSearchParams` request bodies as field maps instead of
  `[object FormData]`
* Changed: `application/json` bodies captured through the WebView bridge
  are now parsed into `Map`/`List` like every other transport (previously
  left as a raw string) — update any code comparing
  `call.response.body` to a JSON string literal
* `SamseerHttpResponse` gained a `contentType` field (mirroring
  `SamseerHttpRequest`); `Samseer.recordResponse` gained an optional
  `contentType` parameter
* Example app: added a **Content types** section exercising every supported
  type end-to-end — `application/json`, `multipart/form-data`,
  `application/x-www-form-urlencoded`, `text/plain`, `text/html`,
  `application/xml`, `application/octet-stream`, `application/pdf`,
  `text/csv`, and `image/png`/`image/jpeg` — plus a `dart:io HttpClient`
  tile that specifically demonstrates the request headers/body capture fix

## 0.4.0

* New: **Copy Request Body** button on the Request tab — copies the formatted request body to the clipboard; disabled when there is no body
* New: **Copy Response Body** button on the Response tab — copies the formatted response body to the clipboard; disabled when there is no body
* New: **Copy URL** button on the Overview tab — copies `METHOD URL` (e.g. `GET https://api.example.com/users`) to the clipboard
* `Exporter`: added `buildRequestBody` and `buildResponseBody` helpers

## 0.3.3

* Removed theme switching — inspector now always renders in dark mode, reducing
  complexity and eliminating host-app theme bleed
* Fix: `StatsScreen` now wrapped with `SamseerTheme` for consistent dark mode
  across all screens
* Fix: endpoint text in `CallDetailScreen` AppBar is now white and bold,
  independent of the host app's `textTheme`
* Removed: `themeMode` field removed from `SamseerConfiguration`

## 0.3.2

* Fix: `CallDetailScreen` now wraps its `Scaffold` with `SamseerTheme` so
  the back button and copy icons use the correct foreground color regardless
  of the host app's theme (previously they could appear white in dark mode)

## 0.3.1

* Re-publish to retry pub.dev analysis. v0.3.0 was scored 70/160 because the
  pub.dev analyzer's dependency resolver hit a transient upstream outage
  (advisories endpoint failed), which cascaded into 0/50 static analysis,
  0/20 platform support, and 0/10 dartdoc coverage. No code changes — `pana`
  locally reports 160/160.

## 0.3.0

* New: WebView inspector support — capture XHR and `fetch` calls happening
  inside any WebView page (think Chrome DevTools' Network tab) by injecting
  `webViewInterceptorScript` and forwarding events to
  `samseer.recordWebViewEvent(...)`. Samseer itself does **not** depend on
  `flutter_inappwebview`; the host app wires the script + JavaScript handler
  to whichever WebView library it uses.
* New: public recording API on `Samseer` — `recordRequest`, `recordResponse`,
  `recordError` — so any custom transport (WebView, GraphQL, gRPC, …) can
  feed calls into the inspector.

## 0.2.2

* Fix: Dio interceptor now serializes custom request body objects (classes
  with `toJson()`) so the inspector shows the actual JSON sent on the wire
  instead of the Dart object's `toString()`

## 0.2.1

* Docs: new "Notifications (optional)" section in the README showing how to
  bridge `samseer.callsStream` into `flutter_local_notifications` (or any
  notification stack) — Samseer itself stays dependency-free
* Example: added `SamseerNotificationBridge` and wired it into the example
  app so users can copy a working reference end-to-end

## 0.2.0

* New: top-of-screen `SamseerToast` notification with slide-down animation,
  variants (neutral/success/warning/error), and auto-dismiss
* Removed `share_plus` and `path_provider` dependencies — copy-to-clipboard
  is now used everywhere, with size-aware feedback (warns above 1 MB)
* "Copy as JSON" replaces the old "Export & Share" action in the inspector menu
* Removed share IconButton and Share button on the cURL tab — Copy buttons cover
  the workflow and the UI is leaner
* `Exporter` API: removed `shareAsJson`, `shareCurl`, `shareCallDump`,
  `originFor`. Added `buildJsonExport` and `formatSize`
* Flat chip styling — filter row no longer shows tonal shadow under chips
* Bumped major versions: `google_fonts ^8.1.0`, `intl ^0.20.2`,
  `sensors_plus ^7.0.0`
* Pub.dev score: 160/160

## 0.1.0

Initial release.

* Multi HTTP client support: Dio, http (package), HttpClient (dart:io)
* Material 3 inspector UI with light & dark themes
* Call list with search, status & method filters
* Tabbed call detail: Overview, Request, Response, cURL
* JSON viewer with syntax highlighting
* Stats screen with success rate, average duration, totals
* Shake-to-open inspector
* Floating inspector bubble (draggable, live call count)
* Export calls to JSON file & share
* In-memory storage with configurable max calls
* Single dependency — no separate adapter packages required
