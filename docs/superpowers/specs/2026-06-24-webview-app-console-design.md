# Design: WebView + App Console for Samseer

**Date:** 2026-06-24
**Status:** Approved — ready for implementation planning

## Summary

Samseer currently captures HTTP traffic (Dio, `http`, `dart:io HttpClient`, and
WebView XHR/`fetch`) and presents it in a Material 3 inspector. This feature adds
a **Console** that captures and displays log output from two sources:

- **WebView** — `console.log/info/warn/error/debug`, uncaught JS errors, and
  unhandled promise rejections, captured by extending the existing injected JS
  interceptor (no new dependency).
- **App (Dart side)** — `print` / `debugPrint`, Flutter framework errors, and
  uncaught async errors, captured by wrapping `runApp` in a logging zone.

Both sources feed one unified Console screen, reached via a new bottom
`NavigationBar` (Network / Console). Entries are filterable by **level** and
**source** using capsule chips, consistent with the existing HTTP status filters.

A core quality goal: console output must be **readable** — objects render as
pretty JSON rather than the browser's default `[object Object]` coercion.

## Goals

- Capture WebView console output and JS errors with no extra dependency and no
  change to existing WebView wiring.
- Capture Dart-side `print`/`debugPrint` and uncaught errors via an opt-in
  one-line `runApp` wrapper.
- Surface WebView/network errors into the Console (errors only).
- Unified Console screen with search and capsule filters for level and source.
- Render object/array arguments as readable, pretty-printed JSON.

## Non-goals

- Capturing `dart:developer` `log()` calls (not globally interceptable without
  invasive hooks). Out of scope.
- Echoing successful (2xx/3xx) HTTP responses into the Console. Only errors are
  bridged. (See Open Decisions — resolved errors-only.)
- Capturing arbitrary native (Android/iOS) platform logs.

## Data model

New model file `lib/src/model/console_log.dart`:

```dart
enum SamseerLogLevel { log, info, warn, error, debug }
enum SamseerLogSource { app, webView }

class SamseerConsoleLog {
  final int id;                 // from SamseerCore.nextId()
  final SamseerLogLevel level;
  final SamseerLogSource source;
  final String message;         // already-formatted, readable text
  final List<Object?>? data;    // structured args (objects/arrays) for pretty JSON in detail
  final String? stackTrace;     // present for errors / rejections
  final DateTime time;
}
```

`message` is the display string (used in the list and as the primary copy
target). `data` carries the structured arguments so the detail view can
pretty-print objects/arrays with the existing `JsonViewer`. `stackTrace` is
populated for error-level entries when available.

## Storage

`SamseerStorage` gains a second ring buffer that mirrors the existing call
buffer exactly:

- `List<SamseerConsoleLog> consoleLogs` (newest first).
- `Stream<List<SamseerConsoleLog>> consoleStream` (broadcast).
- `addConsoleLog(SamseerConsoleLog)` — appends, trims to
  `maxConsoleLogsCount`, emits.
- `clear()` clears **both** the call buffer and the console buffer and emits on
  both streams.
- `dispose()` closes both stream controllers.

Cap is a new config field (see Configuration). Default 500 entries.

## Capture mechanisms

### WebView (extends existing JS interceptor)

Extend `webViewInterceptorScript` in `lib/src/feature/webview_inspector.dart`:

1. **Console patching** — wrap `console.log/info/warn/error/debug`. Each call
   forwards the original (so the WebView's own devtools still see it) and sends:
   `{ kind: 'log', level, message, data }`.
2. **Uncaught errors** — `window.addEventListener('error', ...)` and
   `window.addEventListener('unhandledrejection', ...)` send `error`-level
   entries with `message` and `stack` where available.
3. **Readable serialization (`[object Object]` fix)** — a `formatArgs(args)`
   helper:
   - strings → as-is;
   - numbers/booleans/null/undefined → `String()`;
   - functions → `[Function: name]`;
   - DOM nodes → `[TagName#id.class]` style summary;
   - objects/arrays → `JSON.stringify` with a **circular-safe replacer**
     (replaces seen references with `"[Circular]"`);
   - multiple args joined with a single space (mirrors browser console);
   - any serialization failure falls back to a safe `String()` and **never
     throws** into the host page.

   Objects/arrays are *also* passed through in `data` (post replacer) so the
   Dart detail view can render structured JSON.

All sends go through the existing `send()` bridge to the `samseer_webview`
handler. Idempotent install guard (`window.__samseer_installed`) is unchanged.
**No change is required to existing app WebView wiring** — the same handler that
already forwards to `recordWebViewEvent` now also receives `log` events.

### App (Dart side)

New helper on `Samseer`:

```dart
T captureLogs<T>(T Function() body);
```

Implementation wraps `body` in `runZonedGuarded` with a `ZoneSpecification`
whose `print` handler records a `log`-level `SamseerConsoleLog`
(`source: app`) **and then forwards to the parent zone's print** so IDE/console
output is unaffected. Inside the zone it also installs:

- `FlutterError.onError` → records `error`-level entries with the framework
  error + stack (chaining to the previous handler).
- `PlatformDispatcher.instance.onError` → records uncaught async errors
  (returns `true`/chains as appropriate).
- `runZonedGuarded`'s `onError` → records uncaught zone errors.

Typical usage:

```dart
void main() {
  samseer.captureLogs(() => runApp(const MyApp()));
}
```

`debugPrint` routes through `print`, so it is captured automatically. WebView
capture requires none of this.

### Network errors → Console

In `SamseerWebViewDispatcher._onError` (and, gated by config, on 4xx/5xx
responses — default off; errors-only on by default), append an `error`-level
`SamseerConsoleLog` tagged `source: webView` summarizing the failed call
(method, URL, message). This makes failures visible in both Network and Console
without duplicating successful traffic.

## UI

### Inspector shell

`CallListScreen` becomes a thin shell:

- Holds a bottom `NavigationBar` with two destinations: **Network** and
  **Console**. The Console destination shows a live count badge driven by
  `consoleStream`.
- Body is an `IndexedStack` of `_NetworkView` (the current list + search +
  status filters, extracted unchanged) and `_ConsoleView`.
- AppBar actions (Stats, overflow menu) remain. Overflow "Clear All" clears both
  buffers (matching storage `clear()`).

### Console view

Reuses the proven Network layout:

- A search `TextField` (filters on message text and source).
- **Two capsule rows** (`ChoiceChip`s styled identically to the existing
  `_FilterRow`):
  - **Level:** All / Log / Info / Warn / Error
  - **Source:** All / App / WebView
- A `StreamBuilder<List<SamseerConsoleLog>>` over `consoleStream` rendering a
  `ListView`. Empty state mirrors the existing `EmptyState` widget.

Each row tile shows: a color-coded level indicator (warn = amber, error = red,
others = neutral, following `SamseerTheme`), a small source chip (App / WebView),
a timestamp, and the formatted `message` in a monospaced font, truncated to a
couple of lines.

Tapping a tile opens a Console detail view showing the full message, the
pretty-printed `data` (via the existing `JsonViewer`) when present, and the
stack trace for errors. A copy button copies the formatted message (and stack,
if present).

## Public API & configuration

`lib/samseer.dart`:

- New method `T captureLogs<T>(T Function() body)`.
- `recordWebViewEvent` is unchanged in signature; the dispatcher now also
  handles `kind: 'log'`.
- New exports: `SamseerConsoleLog`, `SamseerLogLevel`, `SamseerLogSource`.

`lib/src/core/samseer_configuration.dart`:

- `int maxConsoleLogsCount` — default 500.
- `bool captureNetworkErrorsInConsole` — default `true`.

## Testing

Dart unit tests (no widget/JS runtime needed):

- **Storage:** console ring buffer appends newest-first, trims to
  `maxConsoleLogsCount`, emits on `consoleStream`; `clear()` empties both
  buffers.
- **Dispatcher:** `kind: 'log'` maps level strings to `SamseerLogLevel`
  (including unknown → `log`), source defaults to `webView`, `data` preserved,
  stack captured for errors.
- **Network bridging:** an `err` event (and, when enabled, a 5xx response)
  produces an `error`-level console entry tagged `webView`.
- **Serializer payloads:** dispatcher correctly handles representative
  payloads (object, array, multiple args, circular-replaced) producing the
  expected `message`/`data`.

The JS serializer itself is exercised indirectly via the demo page; its
contract (no `[object Object]`, circular-safe, never throws) is documented in
the script and verified through the payload shapes the dispatcher receives.

## Example app updates (required — for manual testing)

The example app under `example/` must be updated so the feature is testable
end to end. This is a first-class deliverable, not optional polish:

- **`example/lib/main.dart`** — wrap `runApp` in `samseer.captureLogs(() => ...)`
  so Dart-side `print`/`debugPrint`/errors are captured. Add a couple of buttons
  (or a debug panel) on the home screen that emit App-side logs: a plain
  `print`, a `debugPrint`, a `print` of a Map/List (to prove readable rendering),
  and a deliberate uncaught error to exercise error capture.
- **`example/lib/samseer_webview_demo_page.dart`** — extend the demo HTML with
  buttons that exercise the WebView console path:
  - `console.log` / `console.warn` / `console.error` with plain strings;
  - `console.log` of an **object and an array** (this is the `[object Object]`
    case — must show readable JSON, not `[object Object]`);
  - `console.log` with **multiple mixed args**;
  - a button that throws an uncaught error and one that rejects a promise
    (exercises `window.onerror` / `unhandledrejection`);
  - a fetch to a failing URL (exercises network-error → Console bridging).
- The existing WebView wiring (`webViewInterceptorScript` user script +
  `samseer_webview` handler → `recordWebViewEvent`) is unchanged; confirm the
  console events flow through it without modification.

Manual test path: run the example, trigger app + WebView logs, open the
inspector, switch to the Console tab, and verify filtering by level and source,
readable object rendering, and tap-through to detail.

## Documentation

- README: add a Console section under the WebView integration — how it appears,
  the `captureLogs` wrapper for Dart logs, and a note that WebView console needs
  no extra wiring.
- Update the feature bullet list and CHANGELOG; bump version (minor, e.g.
  `0.5.0`).

## Open decisions (resolved)

- **Bridge non-error HTTP responses into Console?** Resolved: **errors only**,
  gated by `captureNetworkErrorsInConsole` (default `true`). 2xx/3xx are never
  echoed.
