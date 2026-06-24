# WebView + App Console Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a unified Console to Samseer that captures WebView `console.*`/JS errors and Flutter-app `print`/errors, viewable in a new bottom-nav Console tab with level + source filter capsules and readable (non-`[object Object]`) object rendering.

**Architecture:** A new `SamseerConsoleLog` model is stored in a second ring buffer inside `SamseerStorage` (mirroring the existing call buffer). WebView logs arrive through the existing `samseer_webview` JS bridge — the injected JS string gains console patching, error listeners, and a circular-safe serializer; the `SamseerWebViewDispatcher` gains a `log` event branch and bridges network errors into the console. App logs are captured by a `Samseer.captureLogs` zone wrapper around `runApp`. The inspector screen becomes a thin shell hosting a `NavigationBar` over an `IndexedStack` of the existing Network view and a new Console view.

**Tech Stack:** Dart/Flutter (Material 3), `flutter_test`. No new package dependencies.

## Global Constraints

- No new package dependencies — WebView capture rides the existing JS bridge; app capture uses `dart:async`/`dart:ui` only. (Copied from spec: "no extra dependency".)
- Dark-mode inspector only — use `SamseerTheme.theme()` and `colorScheme` tokens; do not add light-mode branches.
- Environment floors: `sdk: ^3.5.0`, `flutter: ">=3.19.0"` (enables `PlatformDispatcher.instance.onError`).
- Existing WebView wiring (`webViewInterceptorScript` user script + `samseer_webview` handler → `recordWebViewEvent`) must keep working unchanged — additive only.
- Follow existing patterns: ring buffer via `Queue`, broadcast `StreamController`, `ChoiceChip` filter rows, `SamseerToast` for copy feedback, `JsonViewer` for structured data.
- Capture scope: `console.log/info/warn/error/debug` + `window.onerror` + `unhandledrejection` + Dart `print`/`debugPrint`/`FlutterError.onError`/`PlatformDispatcher.onError` + WebView network errors (errors only; never echo 2xx/3xx).

---

### Task 1: Console model, storage buffer, configuration

**Files:**
- Create: `lib/src/model/console_log.dart`
- Modify: `lib/src/core/samseer_configuration.dart`
- Modify: `lib/src/core/samseer_storage.dart`
- Modify: `lib/src/core/samseer_core.dart`
- Modify: `lib/samseer.dart` (exports only)
- Test: `test/console_storage_test.dart`

**Interfaces:**
- Produces:
  - `enum SamseerLogLevel { log, info, warn, error, debug }`
  - `enum SamseerLogSource { app, webView }`
  - `class SamseerConsoleLog` with const ctor `({required int id, required SamseerLogLevel level, required SamseerLogSource source, required String message, required DateTime time, List<Object?>? data, String? stackTrace})` and `Map<String,dynamic> toJson()`
  - `SamseerLogLevel samseerLogLevelFromString(Object? raw)` (unknown → `SamseerLogLevel.log`)
  - `SamseerStorage` gains: `consoleLogs` getter (`List<SamseerConsoleLog>`, newest first), `consoleStream` getter (`Stream<List<SamseerConsoleLog>>`), `addConsoleLog(SamseerConsoleLog)`; ctor param `maxConsoleLogsCount` (default 500); `clear()` empties both buffers; `dispose()` closes both controllers
  - `SamseerCore.addConsoleLog(SamseerConsoleLog)`
  - `SamseerConfiguration` gains `int maxConsoleLogsCount` (default 500) and `bool captureNetworkErrorsInConsole` (default true), both in ctor + `copyWith`

- [ ] **Step 1: Write the failing test**

Create `test/console_storage_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:samseer/samseer.dart';
import 'package:samseer/src/core/samseer_storage.dart';

void main() {
  SamseerConsoleLog log(int id, {SamseerLogLevel level = SamseerLogLevel.log}) {
    return SamseerConsoleLog(
      id: id,
      level: level,
      source: SamseerLogSource.app,
      message: 'msg $id',
      time: DateTime.now(),
    );
  }

  group('SamseerConfiguration console fields', () {
    test('defaults', () {
      const config = SamseerConfiguration();
      expect(config.maxConsoleLogsCount, 500);
      expect(config.captureNetworkErrorsInConsole, true);
    });

    test('copyWith preserves console fields', () {
      const config = SamseerConfiguration(maxConsoleLogsCount: 10);
      final next = config.copyWith(captureNetworkErrorsInConsole: false);
      expect(next.maxConsoleLogsCount, 10);
      expect(next.captureNetworkErrorsInConsole, false);
    });
  });

  group('samseerLogLevelFromString', () {
    test('maps known levels', () {
      expect(samseerLogLevelFromString('info'), SamseerLogLevel.info);
      expect(samseerLogLevelFromString('warn'), SamseerLogLevel.warn);
      expect(samseerLogLevelFromString('warning'), SamseerLogLevel.warn);
      expect(samseerLogLevelFromString('error'), SamseerLogLevel.error);
      expect(samseerLogLevelFromString('debug'), SamseerLogLevel.debug);
    });

    test('unknown falls back to log', () {
      expect(samseerLogLevelFromString('verbose'), SamseerLogLevel.log);
      expect(samseerLogLevelFromString(null), SamseerLogLevel.log);
    });
  });

  group('SamseerStorage console buffer', () {
    test('addConsoleLog keeps newest first and caps at max', () {
      final storage = SamseerStorage(maxConsoleLogsCount: 3);
      for (var i = 1; i <= 5; i++) {
        storage.addConsoleLog(log(i));
      }
      expect(storage.consoleLogs.map((l) => l.id), [5, 4, 3]);
      storage.dispose();
    });

    test('clear empties both calls and console buffers', () {
      final storage = SamseerStorage();
      storage.addConsoleLog(log(1));
      storage.clear();
      expect(storage.consoleLogs, isEmpty);
      storage.dispose();
    });

    test('consoleStream emits on add', () async {
      final storage = SamseerStorage();
      final future = storage.consoleStream.first;
      storage.addConsoleLog(log(1));
      final emitted = await future;
      expect(emitted.single.id, 1);
      storage.dispose();
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/airlangga/Documents/sandbox/samseer && flutter test test/console_storage_test.dart`
Expected: FAIL — `SamseerConsoleLog`/`SamseerLogLevel`/`samseerLogLevelFromString`/`maxConsoleLogsCount` undefined (compile errors).

- [ ] **Step 3: Create the model file**

Create `lib/src/model/console_log.dart`:

```dart
import 'package:flutter/foundation.dart';

/// Severity of a captured console entry.
enum SamseerLogLevel { log, info, warn, error, debug }

/// Origin of a captured console entry.
enum SamseerLogSource { app, webView }

/// A single captured log line from the Flutter app or a WebView.
@immutable
class SamseerConsoleLog {
  const SamseerConsoleLog({
    required this.id,
    required this.level,
    required this.source,
    required this.message,
    required this.time,
    this.data,
    this.stackTrace,
  });

  final int id;
  final SamseerLogLevel level;
  final SamseerLogSource source;

  /// Already-formatted, readable message text.
  final String message;

  /// Structured arguments (objects/arrays) for pretty-printing in the detail
  /// view. Null when the entry carried no structured data.
  final List<Object?>? data;

  /// Stack trace for error-level entries, when available.
  final String? stackTrace;

  final DateTime time;

  Map<String, dynamic> toJson() => {
        'id': id,
        'level': level.name,
        'source': source.name,
        'message': message,
        'data': data,
        'stackTrace': stackTrace,
        'time': time.toIso8601String(),
      };
}

/// Maps a JS console level string to [SamseerLogLevel]. Unknown values
/// (including null) fall back to [SamseerLogLevel.log].
SamseerLogLevel samseerLogLevelFromString(Object? raw) {
  switch (raw?.toString()) {
    case 'info':
      return SamseerLogLevel.info;
    case 'warn':
    case 'warning':
      return SamseerLogLevel.warn;
    case 'error':
      return SamseerLogLevel.error;
    case 'debug':
      return SamseerLogLevel.debug;
    default:
      return SamseerLogLevel.log;
  }
}
```

- [ ] **Step 4: Add configuration fields**

In `lib/src/core/samseer_configuration.dart`, add the two fields to the ctor, the field declarations, and `copyWith`.

Add to the constructor parameter list (after `this.shakeThreshold = 20,`):

```dart
    this.maxConsoleLogsCount = 500,
    this.captureNetworkErrorsInConsole = true,
```

Add field declarations (after the `shakeThreshold` field):

```dart
  /// Max number of console log entries to keep in memory. Older entries are
  /// evicted FIFO.
  final int maxConsoleLogsCount;

  /// Whether WebView/network errors are also surfaced as error-level entries
  /// in the Console. Successful (2xx/3xx) responses are never echoed.
  final bool captureNetworkErrorsInConsole;
```

In `copyWith`, add params and pass-through:

```dart
  SamseerConfiguration copyWith({
    int? maxCallsCount,
    bool? showInspectorOnShake,
    bool? showFloatingBubble,
    TextDirection? directionality,
    double? shakeThreshold,
    int? maxConsoleLogsCount,
    bool? captureNetworkErrorsInConsole,
  }) {
    return SamseerConfiguration(
      maxCallsCount: maxCallsCount ?? this.maxCallsCount,
      showInspectorOnShake: showInspectorOnShake ?? this.showInspectorOnShake,
      showFloatingBubble: showFloatingBubble ?? this.showFloatingBubble,
      directionality: directionality ?? this.directionality,
      shakeThreshold: shakeThreshold ?? this.shakeThreshold,
      maxConsoleLogsCount: maxConsoleLogsCount ?? this.maxConsoleLogsCount,
      captureNetworkErrorsInConsole:
          captureNetworkErrorsInConsole ?? this.captureNetworkErrorsInConsole,
    );
  }
```

- [ ] **Step 5: Extend storage with the console buffer**

In `lib/src/core/samseer_storage.dart`:

Add the import at the top (after the existing model imports):

```dart
import '../model/console_log.dart';
```

Change the constructor and add the console field declarations:

```dart
  SamseerStorage({this.maxCallsCount = 1000, this.maxConsoleLogsCount = 500});

  final int maxCallsCount;
  final int maxConsoleLogsCount;
  final Queue<SamseerHttpCall> _calls = Queue<SamseerHttpCall>();
  final Queue<SamseerConsoleLog> _logs = Queue<SamseerConsoleLog>();
  final StreamController<List<SamseerHttpCall>> _controller =
      StreamController<List<SamseerHttpCall>>.broadcast();
  final StreamController<List<SamseerConsoleLog>> _logController =
      StreamController<List<SamseerConsoleLog>>.broadcast();
```

Add getters near the existing `calls` getter:

```dart
  /// Reactive stream of console entries. Latest snapshot wins.
  Stream<List<SamseerConsoleLog>> get consoleStream => _logController.stream;

  /// Synchronous snapshot of all console entries, newest first.
  List<SamseerConsoleLog> get consoleLogs => _logs.toList(growable: false);
```

Add the `addConsoleLog` method (after `addCall`):

```dart
  void addConsoleLog(SamseerConsoleLog log) {
    _logs.addFirst(log);
    while (_logs.length > maxConsoleLogsCount) {
      _logs.removeLast();
    }
    _emitLogs();
  }
```

Update `clear()` to empty both buffers:

```dart
  void clear() {
    _calls.clear();
    _logs.clear();
    _emit();
    _emitLogs();
  }
```

Update `dispose()` to close both controllers:

```dart
  void dispose() {
    _controller.close();
    _logController.close();
  }
```

Add the `_emitLogs` helper (next to `_emit`):

```dart
  void _emitLogs() {
    if (_logController.isClosed) return;
    _logController.add(_logs.toList(growable: false));
  }
```

- [ ] **Step 6: Wire core to pass console cap and expose addConsoleLog**

In `lib/src/core/samseer_core.dart`:

Add the import (after the existing model imports):

```dart
import '../model/console_log.dart';
```

Change the storage construction inside the constructor body:

```dart
    storage = SamseerStorage(
      maxCallsCount: this.configuration.maxCallsCount,
      maxConsoleLogsCount: this.configuration.maxConsoleLogsCount,
    );
```

Add the method (after `addError`):

```dart
  void addConsoleLog(SamseerConsoleLog log) => storage.addConsoleLog(log);
```

- [ ] **Step 7: Export the new model types**

In `lib/samseer.dart`, add the import (after the other `src/model` imports):

```dart
import 'src/model/console_log.dart';
```

Add the export (after the other `src/model` exports):

```dart
export 'src/model/console_log.dart'
    show SamseerConsoleLog, SamseerLogLevel, SamseerLogSource;
```

> Note: `samseerLogLevelFromString` is intentionally NOT exported (internal helper). The test imports it via `package:samseer/src/model/console_log.dart`.

Fix the test import in `test/console_storage_test.dart` Step 1 — it imports `samseerLogLevelFromString` from the public library; change that import line to also pull from src:

```dart
import 'package:samseer/src/model/console_log.dart'
    show samseerLogLevelFromString;
```

(Place it alongside the existing `import 'package:samseer/src/core/samseer_storage.dart';`.)

- [ ] **Step 8: Run tests to verify they pass**

Run: `cd /Users/airlangga/Documents/sandbox/samseer && flutter test test/console_storage_test.dart`
Expected: PASS (all groups).

- [ ] **Step 9: Analyze**

Run: `cd /Users/airlangga/Documents/sandbox/samseer && flutter analyze lib test`
Expected: No issues.

- [ ] **Step 10: Commit**

```bash
cd /Users/airlangga/Documents/sandbox/samseer
git add lib/src/model/console_log.dart lib/src/core/samseer_configuration.dart lib/src/core/samseer_storage.dart lib/src/core/samseer_core.dart lib/samseer.dart test/console_storage_test.dart
git commit -m "feat: add console log model, storage buffer, and config"
```

---

### Task 2: Dispatcher `log` handling + network-error bridging

**Files:**
- Modify: `lib/src/feature/webview_inspector.dart` (Dart `SamseerWebViewDispatcher` only — JS string handled in Task 4)
- Test: `test/console_dispatcher_test.dart`

**Interfaces:**
- Consumes: `SamseerCore.addConsoleLog`, `SamseerCore.nextId`, `SamseerCore.configuration.captureNetworkErrorsInConsole`, `samseerLogLevelFromString`, `SamseerConsoleLog`, `SamseerLogLevel`, `SamseerLogSource`. Public test entry: `Samseer.recordWebViewEvent(Object?)`, `Samseer.consoleLogs`, `Samseer.calls`.
- Produces: dispatcher handles `{kind:'log', level, message, data, stack}` (no `cid` required) → app/webView console entry; `_onError` and `_onResponse` bridge errors/5xx-4xx? (errors only) into the console when enabled.

- [ ] **Step 1: Write the failing test**

Create `test/console_dispatcher_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:samseer/samseer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WebView console events', () {
    test('log event becomes a webView console entry', () {
      final samseer = Samseer(
        configuration: const SamseerConfiguration(showInspectorOnShake: false),
      );
      samseer.recordWebViewEvent({
        'kind': 'log',
        'level': 'warn',
        'message': 'hello {"a":1}',
        'data': [
          {'a': 1}
        ],
      });
      final logs = samseer.consoleLogs;
      expect(logs, hasLength(1));
      expect(logs.single.level, SamseerLogLevel.warn);
      expect(logs.single.source, SamseerLogSource.webView);
      expect(logs.single.message, 'hello {"a":1}');
      expect(logs.single.data, [
        {'a': 1}
      ]);
      samseer.dispose();
    });

    test('unknown level falls back to log', () {
      final samseer = Samseer(
        configuration: const SamseerConfiguration(showInspectorOnShake: false),
      );
      samseer.recordWebViewEvent(
          {'kind': 'log', 'level': 'trace', 'message': 'x'});
      expect(samseer.consoleLogs.single.level, SamseerLogLevel.log);
      samseer.dispose();
    });

    test('error event carries stack', () {
      final samseer = Samseer(
        configuration: const SamseerConfiguration(showInspectorOnShake: false),
      );
      samseer.recordWebViewEvent({
        'kind': 'log',
        'level': 'error',
        'message': 'boom',
        'stack': 'at foo (app.js:1)',
      });
      expect(samseer.consoleLogs.single.stackTrace, 'at foo (app.js:1)');
      samseer.dispose();
    });
  });

  group('network-error bridging', () {
    test('err event also creates an error console entry when enabled', () {
      final samseer = Samseer(
        configuration: const SamseerConfiguration(showInspectorOnShake: false),
      );
      samseer.recordWebViewEvent({
        'kind': 'req',
        'cid': 'c1',
        'method': 'GET',
        'url': 'https://api.example.com/x',
        'headers': {},
      });
      samseer.recordWebViewEvent(
          {'kind': 'err', 'cid': 'c1', 'message': 'Network error'});
      // Call recorded with error.
      expect(samseer.calls.single.hasError, true);
      // Console entry bridged.
      final consoleErrors = samseer.consoleLogs
          .where((l) => l.level == SamseerLogLevel.error)
          .toList();
      expect(consoleErrors, hasLength(1));
      expect(consoleErrors.single.source, SamseerLogSource.webView);
      expect(consoleErrors.single.message, contains('api.example.com'));
      samseer.dispose();
    });

    test('bridging disabled suppresses the console entry', () {
      final samseer = Samseer(
        configuration: const SamseerConfiguration(
          showInspectorOnShake: false,
          captureNetworkErrorsInConsole: false,
        ),
      );
      samseer.recordWebViewEvent({
        'kind': 'req',
        'cid': 'c1',
        'method': 'GET',
        'url': 'https://api.example.com/x',
        'headers': {},
      });
      samseer.recordWebViewEvent(
          {'kind': 'err', 'cid': 'c1', 'message': 'Network error'});
      expect(samseer.consoleLogs, isEmpty);
      samseer.dispose();
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/airlangga/Documents/sandbox/samseer && flutter test test/console_dispatcher_test.dart`
Expected: FAIL — `Samseer.consoleLogs` getter undefined (added in Step 3) and/or no console entries produced.

- [ ] **Step 3: Add `consoleLogs`/`consoleStream` getters to `Samseer`**

In `lib/samseer.dart`, add inside the `Samseer` class (after the `callsStream` getter):

```dart
  /// Snapshot of all currently recorded console entries (newest first).
  List<SamseerConsoleLog> get consoleLogs => _core.storage.consoleLogs;

  /// Reactive stream of recorded console entries.
  Stream<List<SamseerConsoleLog>> get consoleStream =>
      _core.storage.consoleStream;
```

- [ ] **Step 4: Extend the dispatcher**

In `lib/src/feature/webview_inspector.dart`:

Add the import (after the existing model imports):

```dart
import '../model/console_log.dart';
```

Add a URL tracking map next to `_ids`:

```dart
  final Map<String, int> _ids = <String, int>{};
  final Map<String, String> _urls = <String, String>{};
```

Replace the `dispatch` method so `log` is handled without requiring `cid`:

```dart
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
```

In `_onRequest`, record the URL for later bridging — add after `_ids[cid] = id;`:

```dart
    _urls[cid] = urlString;
```

In `_onResponse`, drop the tracked URL — add after `final id = _ids.remove(cid);`:

```dart
    _urls.remove(cid);
```

Replace `_onError` with the bridging version:

```dart
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
```

Add the `_onLog` method (after `_onError`):

```dart
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
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd /Users/airlangga/Documents/sandbox/samseer && flutter test test/console_dispatcher_test.dart`
Expected: PASS (both groups).

- [ ] **Step 6: Analyze**

Run: `cd /Users/airlangga/Documents/sandbox/samseer && flutter analyze lib test`
Expected: No issues.

- [ ] **Step 7: Commit**

```bash
cd /Users/airlangga/Documents/sandbox/samseer
git add lib/src/feature/webview_inspector.dart lib/samseer.dart test/console_dispatcher_test.dart
git commit -m "feat: dispatch webview console logs and bridge network errors"
```

---

### Task 3: App-side capture — `Samseer.captureLogs`

**Files:**
- Modify: `lib/samseer.dart`
- Test: `test/capture_logs_test.dart`

**Interfaces:**
- Consumes: `SamseerCore.addConsoleLog`, `SamseerCore.nextId`, `SamseerConsoleLog`, `SamseerLogLevel`, `SamseerLogSource`.
- Produces: `T? captureLogs<T>(T Function() body)` on `Samseer` — wraps `body` in `runZonedGuarded` capturing `print` (forwarded to parent), `FlutterError.onError`, `PlatformDispatcher.instance.onError`, and zone errors as `source: app` entries.

- [ ] **Step 1: Write the failing test**

Create `test/capture_logs_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:samseer/samseer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('captureLogs records print as an app log entry', () {
    final samseer = Samseer(
      configuration: const SamseerConfiguration(showInspectorOnShake: false),
    );
    samseer.captureLogs(() {
      print('hello from app');
    });
    final logs = samseer.consoleLogs;
    expect(logs, hasLength(1));
    expect(logs.single.message, 'hello from app');
    expect(logs.single.level, SamseerLogLevel.log);
    expect(logs.single.source, SamseerLogSource.app);
    samseer.dispose();
  });

  test('captureLogs returns the body result', () {
    final samseer = Samseer(
      configuration: const SamseerConfiguration(showInspectorOnShake: false),
    );
    final result = samseer.captureLogs<int>(() => 42);
    expect(result, 42);
    samseer.dispose();
  });

  test('captureLogs records uncaught async zone errors', () async {
    final samseer = Samseer(
      configuration: const SamseerConfiguration(showInspectorOnShake: false),
    );
    samseer.captureLogs(() {
      Future<void>.error(StateError('async boom'));
    });
    // Let the microtask/event queue flush.
    await Future<void>.delayed(const Duration(milliseconds: 10));
    final errors = samseer.consoleLogs
        .where((l) => l.level == SamseerLogLevel.error)
        .toList();
    expect(errors, isNotEmpty);
    expect(errors.first.message, contains('async boom'));
    expect(errors.first.source, SamseerLogSource.app);
    samseer.dispose();
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/airlangga/Documents/sandbox/samseer && flutter test test/capture_logs_test.dart`
Expected: FAIL — `captureLogs` not defined.

- [ ] **Step 3: Implement `captureLogs`**

In `lib/samseer.dart`, add the imports (after `import 'package:flutter/material.dart';`):

```dart
import 'dart:async';
import 'dart:ui' show PlatformDispatcher;
```

Add the method to the `Samseer` class (after `recordWebViewEvent`):

```dart
  /// Run [body] inside a zone that captures Dart-side logs into the Console.
  ///
  /// Captures `print`/`debugPrint` (level [SamseerLogLevel.log]), Flutter
  /// framework errors, uncaught async errors, and zone errors (level
  /// [SamseerLogLevel.error]) — all tagged [SamseerLogSource.app]. Output is
  /// still forwarded to the original `print` so IDE logs are unaffected.
  ///
  /// ```dart
  /// void main() {
  ///   samseer.captureLogs(() => runApp(const MyApp()));
  /// }
  /// ```
  T? captureLogs<T>(T Function() body) {
    void recordError(Object error, StackTrace? stack) {
      _core.addConsoleLog(SamseerConsoleLog(
        id: _core.nextId(),
        level: SamseerLogLevel.error,
        source: SamseerLogSource.app,
        message: error.toString(),
        stackTrace: stack?.toString(),
        time: DateTime.now(),
      ));
    }

    return runZonedGuarded<T>(
      () {
        final previousFlutterOnError = FlutterError.onError;
        FlutterError.onError = (FlutterErrorDetails details) {
          _core.addConsoleLog(SamseerConsoleLog(
            id: _core.nextId(),
            level: SamseerLogLevel.error,
            source: SamseerLogSource.app,
            message: details.exceptionAsString(),
            stackTrace: details.stack?.toString(),
            time: DateTime.now(),
          ));
          if (previousFlutterOnError != null) {
            previousFlutterOnError(details);
          } else {
            FlutterError.presentError(details);
          }
        };
        PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
          recordError(error, stack);
          return false;
        };
        return body();
      },
      recordError,
      zoneSpecification: ZoneSpecification(
        print: (Zone self, ZoneDelegate parent, Zone zone, String line) {
          _core.addConsoleLog(SamseerConsoleLog(
            id: _core.nextId(),
            level: SamseerLogLevel.log,
            source: SamseerLogSource.app,
            message: line,
            time: DateTime.now(),
          ));
          parent.print(zone, line);
        },
      ),
    );
  }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /Users/airlangga/Documents/sandbox/samseer && flutter test test/capture_logs_test.dart`
Expected: PASS (all three tests).

- [ ] **Step 5: Analyze**

Run: `cd /Users/airlangga/Documents/sandbox/samseer && flutter analyze lib test`
Expected: No issues.

- [ ] **Step 6: Commit**

```bash
cd /Users/airlangga/Documents/sandbox/samseer
git add lib/samseer.dart test/capture_logs_test.dart
git commit -m "feat: add Samseer.captureLogs zone wrapper for app-side logs"
```

---

### Task 4: Extend the injected JS interceptor (console + errors + serializer)

**Files:**
- Modify: `lib/src/feature/webview_inspector.dart` (the `webViewInterceptorScript` string only)
- Test: `test/webview_script_test.dart`

**Interfaces:**
- Consumes: the existing JS `send(payload)` helper and `samseer_webview` bridge.
- Produces: the injected script now patches `console.log/info/warn/error/debug`, listens for `error`/`unhandledrejection`, and serializes args readably (objects → JSON, never `[object Object]`, circular-safe, never throws). Emits `{kind:'log', level, message, data, stack}` consumed by Task 2's `_onLog`.

> The JS runs only in a real WebView, so the automated test asserts the script *contains* the required hooks (a regression guard). Behavioural verification happens via the example app (Task 6).

- [ ] **Step 1: Write the failing test**

Create `test/webview_script_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:samseer/samseer.dart';

void main() {
  group('webViewInterceptorScript console hooks', () {
    test('patches all console levels', () {
      for (final level in ['log', 'info', 'warn', 'error', 'debug']) {
        expect(
          webViewInterceptorScript.contains("'$level'"),
          isTrue,
          reason: 'script should reference console level $level',
        );
      }
    });

    test('emits log events through the bridge', () {
      expect(webViewInterceptorScript.contains("kind: 'log'"), isTrue);
    });

    test('listens for uncaught errors and rejections', () {
      expect(webViewInterceptorScript.contains("addEventListener('error'"),
          isTrue);
      expect(
          webViewInterceptorScript.contains("'unhandledrejection'"), isTrue);
    });

    test('includes a circular-safe serializer (no [object Object])', () {
      expect(webViewInterceptorScript.contains('safeStringify'), isTrue);
      expect(webViewInterceptorScript.contains('[Circular]'), isTrue);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/airlangga/Documents/sandbox/samseer && flutter test test/webview_script_test.dart`
Expected: FAIL — script does not yet contain `kind: 'log'`, `safeStringify`, etc.

- [ ] **Step 3: Insert the console/serializer JS**

In `lib/src/feature/webview_inspector.dart`, locate the end of the `bodyToString` helper inside the script (the lines):

```js
  function bodyToString(body) {
    if (body == null) return null;
    if (typeof body === 'string') return body;
    try { return String(body); } catch (_) { return null; }
  }
```

Immediately AFTER that closing `}` and BEFORE the `// --- XMLHttpRequest ---` comment, insert:

```js
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
      if (v !== null && typeof v === 'object') {
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
      try { sendLog(level, arguments, null); } catch (_) {}
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
    var msg = (reason && reason.message) ? reason.message : String(reason);
    var stack = (reason && reason.stack) ? reason.stack : null;
    sendLog('error', ['Unhandled rejection: ' + msg], stack);
  });
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /Users/airlangga/Documents/sandbox/samseer && flutter test test/webview_script_test.dart`
Expected: PASS (all four tests).

- [ ] **Step 5: Analyze**

Run: `cd /Users/airlangga/Documents/sandbox/samseer && flutter analyze lib test`
Expected: No issues.

- [ ] **Step 6: Commit**

```bash
cd /Users/airlangga/Documents/sandbox/samseer
git add lib/src/feature/webview_inspector.dart test/webview_script_test.dart
git commit -m "feat: capture webview console output and js errors in injected script"
```

---

### Task 5: Console UI — level colors, filter, view, tile, detail, bottom nav

**Files:**
- Modify: `lib/src/ui/theme/samseer_theme.dart` (add `SamseerColors.forLogLevel`)
- Create: `lib/src/ui/screen/console_view.dart` (the `_ConsoleView` widget + `applyConsoleFilter` + console tile + detail screen)
- Modify: `lib/src/ui/screen/call_list_screen.dart` (extract `_NetworkView`, add bottom `NavigationBar`)
- Test: `test/console_filter_test.dart`

**Interfaces:**
- Consumes: `SamseerCore`, `SamseerConsoleLog`, `SamseerLogLevel`, `SamseerLogSource`, `SamseerTheme`, `JsonViewer`, `EmptyState`, `SamseerToast`.
- Produces:
  - `Color SamseerColors.forLogLevel(SamseerLogLevel level)`
  - `List<SamseerConsoleLog> applyConsoleFilter(List<SamseerConsoleLog> input, {String query, SamseerLogLevel? level, SamseerLogSource? source})` (top-level in `console_view.dart`)
  - `class ConsoleView extends StatefulWidget` (ctor `{required SamseerCore core}`)
  - `CallListScreen` body becomes a `NavigationBar` over `IndexedStack(_NetworkView, ConsoleView)`.

- [ ] **Step 1: Write the failing test**

Create `test/console_filter_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:samseer/samseer.dart';
import 'package:samseer/src/ui/screen/console_view.dart';

void main() {
  SamseerConsoleLog entry(
    int id, {
    SamseerLogLevel level = SamseerLogLevel.log,
    SamseerLogSource source = SamseerLogSource.app,
    String message = 'msg',
  }) {
    return SamseerConsoleLog(
      id: id,
      level: level,
      source: source,
      message: message,
      time: DateTime.now(),
    );
  }

  final logs = [
    entry(1, level: SamseerLogLevel.error, source: SamseerLogSource.webView,
        message: 'network exploded'),
    entry(2, level: SamseerLogLevel.warn, source: SamseerLogSource.app,
        message: 'careful now'),
    entry(3, level: SamseerLogLevel.log, source: SamseerLogSource.app,
        message: 'just info'),
  ];

  test('no filters returns everything', () {
    expect(applyConsoleFilter(logs).length, 3);
  });

  test('level filter', () {
    final r = applyConsoleFilter(logs, level: SamseerLogLevel.error);
    expect(r.map((l) => l.id), [1]);
  });

  test('source filter', () {
    final r = applyConsoleFilter(logs, source: SamseerLogSource.webView);
    expect(r.map((l) => l.id), [1]);
  });

  test('query matches message case-insensitively', () {
    final r = applyConsoleFilter(logs, query: 'EXPLODED');
    expect(r.map((l) => l.id), [1]);
  });

  test('combined level + query', () {
    final r = applyConsoleFilter(logs,
        level: SamseerLogLevel.warn, query: 'careful');
    expect(r.map((l) => l.id), [2]);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/airlangga/Documents/sandbox/samseer && flutter test test/console_filter_test.dart`
Expected: FAIL — `console_view.dart` / `applyConsoleFilter` does not exist.

- [ ] **Step 3: Add the level color helper**

In `lib/src/ui/theme/samseer_theme.dart`, add the import (after `import '../../model/http_call.dart';`):

```dart
import '../../model/console_log.dart';
```

Add this static method to `SamseerColors` (after `forState`):

```dart
  static Color forLogLevel(SamseerLogLevel level) {
    switch (level) {
      case SamseerLogLevel.error:
        return serverError;
      case SamseerLogLevel.warn:
        return clientError;
      case SamseerLogLevel.info:
        return redirect;
      case SamseerLogLevel.debug:
        return loading;
      case SamseerLogLevel.log:
        return loading;
    }
  }
```

- [ ] **Step 4: Create the console view file**

Create `lib/src/ui/screen/console_view.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../core/samseer_core.dart';
import '../../model/console_log.dart';
import '../theme/samseer_theme.dart';
import '../widget/empty_state.dart';
import '../widget/json_viewer.dart';
import '../widget/samseer_toast.dart';

/// Pure filter used by the console list and unit-tested directly.
List<SamseerConsoleLog> applyConsoleFilter(
  List<SamseerConsoleLog> input, {
  String query = '',
  SamseerLogLevel? level,
  SamseerLogSource? source,
}) {
  var result = input;
  if (level != null) {
    result = result.where((l) => l.level == level).toList();
  }
  if (source != null) {
    result = result.where((l) => l.source == source).toList();
  }
  final q = query.trim().toLowerCase();
  if (q.isNotEmpty) {
    result = result.where((l) => l.message.toLowerCase().contains(q)).toList();
  }
  return result;
}

String _levelLabel(SamseerLogLevel level) {
  switch (level) {
    case SamseerLogLevel.log:
      return 'Log';
    case SamseerLogLevel.info:
      return 'Info';
    case SamseerLogLevel.warn:
      return 'Warn';
    case SamseerLogLevel.error:
      return 'Error';
    case SamseerLogLevel.debug:
      return 'Debug';
  }
}

String _sourceLabel(SamseerLogSource source) =>
    source == SamseerLogSource.app ? 'App' : 'WebView';

class ConsoleView extends StatefulWidget {
  const ConsoleView({super.key, required this.core});
  final SamseerCore core;

  @override
  State<ConsoleView> createState() => _ConsoleViewState();
}

class _ConsoleViewState extends State<ConsoleView> {
  String _query = '';
  SamseerLogLevel? _level;
  SamseerLogSource? _source;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: TextField(
            onChanged: (v) => setState(() => _query = v),
            textInputAction: TextInputAction.search,
            decoration: const InputDecoration(
              hintText: 'Search console messages…',
              prefixIcon: Icon(Icons.search),
              isDense: true,
            ),
          ),
        ),
        _LevelFilterRow(
          selected: _level,
          onSelected: (l) => setState(() => _level = l),
        ),
        _SourceFilterRow(
          selected: _source,
          onSelected: (s) => setState(() => _source = s),
        ),
        Expanded(
          child: StreamBuilder<List<SamseerConsoleLog>>(
            stream: widget.core.storage.consoleStream,
            initialData: widget.core.storage.consoleLogs,
            builder: (context, snap) {
              final logs = applyConsoleFilter(
                snap.data ?? const [],
                query: _query,
                level: _level,
                source: _source,
              );
              if (logs.isEmpty) {
                return const EmptyState(
                  title: 'No console output yet',
                  subtitle:
                      'App print()/errors and WebView console logs appear here.',
                  icon: Icons.terminal,
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                itemCount: logs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (context, i) => ConsoleLogTile(
                  log: logs[i],
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ConsoleDetailScreen(log: logs[i]),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class ConsoleLogTile extends StatelessWidget {
  const ConsoleLogTile({super.key, required this.log, required this.onTap});
  final SamseerConsoleLog log;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final accent = SamseerColors.forLogLevel(log.level);
    final time = DateFormat('HH:mm:ss').format(log.time);
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: Color.alphaBlend(
              accent.withValues(alpha: 0.05), cs.surfaceContainerHigh),
          border: Border.all(
            color: cs.outlineVariant.withValues(alpha: 0.3),
            width: 0.8,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration:
                          BoxDecoration(color: accent, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _levelLabel(log.level).toUpperCase(),
                      style: TextStyle(
                        color: accent,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _SourceChip(source: log.source),
                    const Spacer(),
                    Text(
                      time,
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontSize: 11,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  log.message,
                  style: SamseerTheme.mono(context, size: 12),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SourceChip extends StatelessWidget {
  const _SourceChip({required this.source});
  final SamseerLogSource source;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        _sourceLabel(source),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: cs.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _LevelFilterRow extends StatelessWidget {
  const _LevelFilterRow({required this.selected, required this.onSelected});
  final SamseerLogLevel? selected;
  final ValueChanged<SamseerLogLevel?> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          _Capsule(
            label: 'All',
            selected: selected == null,
            onTap: () => onSelected(null),
          ),
          for (final level in SamseerLogLevel.values)
            _Capsule(
              label: _levelLabel(level),
              selected: selected == level,
              onTap: () => onSelected(level),
            ),
        ],
      ),
    );
  }
}

class _SourceFilterRow extends StatelessWidget {
  const _SourceFilterRow({required this.selected, required this.onSelected});
  final SamseerLogSource? selected;
  final ValueChanged<SamseerLogSource?> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          _Capsule(
            label: 'All sources',
            selected: selected == null,
            onTap: () => onSelected(null),
          ),
          for (final source in SamseerLogSource.values)
            _Capsule(
              label: _sourceLabel(source),
              selected: selected == source,
              onTap: () => onSelected(source),
            ),
        ],
      ),
    );
  }
}

class _Capsule extends StatelessWidget {
  const _Capsule({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
        elevation: 0,
        pressElevation: 0,
        shadowColor: Colors.transparent,
        selectedShadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        side: BorderSide.none,
        shape: const StadiumBorder(side: BorderSide.none),
        labelStyle: TextStyle(
          color: selected ? cs.onPrimary : cs.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class ConsoleDetailScreen extends StatelessWidget {
  const ConsoleDetailScreen({super.key, required this.log});
  final SamseerConsoleLog log;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final accent = SamseerColors.forLogLevel(log.level);
    return Theme(
      data: SamseerTheme.theme(),
      child: Scaffold(
        appBar: AppBar(
          title: Row(
            children: [
              Text(
                _levelLabel(log.level).toUpperCase(),
                style: TextStyle(color: accent, fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: 8),
              _SourceChip(source: log.source),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'Copy',
              icon: const Icon(Icons.content_copy_outlined),
              onPressed: () => _copy(context),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(14),
              ),
              child: SelectableText(
                log.message,
                style: SamseerTheme.mono(context),
              ),
            ),
            if (log.data != null) ...[
              const SizedBox(height: 16),
              Text('DATA',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: cs.primary,
                      letterSpacing: 1)),
              const SizedBox(height: 8),
              for (final item in log.data!)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: JsonViewer(value: item),
                  ),
                ),
            ],
            if (log.stackTrace != null) ...[
              const SizedBox(height: 16),
              Text('STACK TRACE',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: cs.primary,
                      letterSpacing: 1)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SelectableText(
                  log.stackTrace!,
                  style: SamseerTheme.mono(context, size: 11),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _copy(BuildContext context) async {
    final buffer = StringBuffer(log.message);
    if (log.stackTrace != null) {
      buffer
        ..write('\n\n')
        ..write(log.stackTrace);
    }
    await Clipboard.setData(ClipboardData(text: buffer.toString()));
    if (!context.mounted) return;
    SamseerToast.show(
      context,
      'Console entry copied',
      variant: SamseerToastVariant.success,
    );
  }
}
```

- [ ] **Step 5: Run the filter test to verify it passes**

Run: `cd /Users/airlangga/Documents/sandbox/samseer && flutter test test/console_filter_test.dart`
Expected: PASS (all five tests).

- [ ] **Step 6: Integrate the bottom nav into `CallListScreen`**

In `lib/src/ui/screen/call_list_screen.dart`:

Add imports (after `import 'call_detail_screen.dart';`):

```dart
import '../../model/console_log.dart';
import 'console_view.dart';
```

Replace the `_CallListScreenState` class's fields and `build` method. The new `build` keeps the existing AppBar + actions, moves the search/filter/list `Column` body into a new `_NetworkView`, and wraps the body in an `IndexedStack` under a `NavigationBar`. Replace from `class _CallListScreenState extends State<CallListScreen> {` down to the end of its `build` method's returned `Theme(...)` (i.e. up to and including the matching closing of `build`) with:

```dart
class _CallListScreenState extends State<CallListScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final config = widget.core.configuration;
    return Theme(
      data: SamseerTheme.theme(),
      child: Directionality(
        textDirection: config.directionality ?? Directionality.of(context),
        child: Scaffold(
          appBar: AppBar(
            title: Text(_tab == 0 ? 'Samseer' : 'Console'),
            actions: [
              IconButton(
                tooltip: 'Stats',
                icon: const Icon(Icons.insights_outlined),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => StatsScreen(core: widget.core),
                  ),
                ),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert),
                onSelected: _onMenu,
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'export', child: Text('Copy as JSON')),
                  PopupMenuItem(value: 'clear', child: Text('Clear All')),
                ],
              ),
            ],
          ),
          body: IndexedStack(
            index: _tab,
            children: [
              _NetworkView(core: widget.core),
              ConsoleView(core: widget.core),
            ],
          ),
          bottomNavigationBar: StreamBuilder<List<SamseerConsoleLog>>(
            stream: widget.core.storage.consoleStream,
            initialData: widget.core.storage.consoleLogs,
            builder: (context, snap) {
              final count = (snap.data ?? const []).length;
              return NavigationBar(
                selectedIndex: _tab,
                onDestinationSelected: (i) => setState(() => _tab = i),
                destinations: [
                  const NavigationDestination(
                    icon: Icon(Icons.travel_explore_outlined),
                    selectedIcon: Icon(Icons.travel_explore),
                    label: 'Network',
                  ),
                  NavigationDestination(
                    icon: Badge.count(
                      count: count,
                      isLabelVisible: count > 0,
                      child: const Icon(Icons.terminal_outlined),
                    ),
                    selectedIcon: Badge.count(
                      count: count,
                      isLabelVisible: count > 0,
                      child: const Icon(Icons.terminal),
                    ),
                    label: 'Console',
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
```

Then move the search + filter + list `Column` into a new stateful `_NetworkView` that owns `_query` and `_filter`. Replace the now-orphaned `_apply` and `_onMenu` ownership: `_onMenu` stays on `_CallListScreenState` (used by the AppBar menu); `_apply` and the search/filter state move into `_NetworkView`. Add this class (place it directly after `_CallListScreenState`):

```dart
class _NetworkView extends StatefulWidget {
  const _NetworkView({required this.core});
  final SamseerCore core;

  @override
  State<_NetworkView> createState() => _NetworkViewState();
}

class _NetworkViewState extends State<_NetworkView> {
  String _query = '';
  _StatusFilter _filter = _StatusFilter.all;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _SearchBar(onChanged: (v) => setState(() => _query = v)),
        _FilterRow(
          selected: _filter,
          onSelected: (f) => setState(() => _filter = f),
        ),
        Expanded(
          child: StreamBuilder<List<SamseerHttpCall>>(
            stream: widget.core.storage.stream,
            initialData: widget.core.storage.calls,
            builder: (context, snap) {
              final calls = _apply(snap.data ?? const []);
              if (calls.isEmpty) {
                return const EmptyState(
                  title: 'No HTTP calls yet',
                  subtitle:
                      'Make a network request and it will show up here.',
                  icon: Icons.travel_explore,
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                itemCount: calls.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, i) => _AnimatedTile(
                  key: ValueKey(calls[i].id),
                  child: CallTile(
                    call: calls[i],
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => CallDetailScreen(
                          core: widget.core,
                          callId: calls[i].id,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  List<SamseerHttpCall> _apply(List<SamseerHttpCall> input) {
    var result = input;
    final q = _query.trim().toLowerCase();
    if (q.isNotEmpty) {
      result = result.where((c) {
        return c.uri.toLowerCase().contains(q) ||
            c.endpoint.toLowerCase().contains(q) ||
            c.method.toLowerCase().contains(q) ||
            (c.status?.toString().contains(q) ?? false);
      }).toList();
    }
    result = result
        .where((c) => switch (_filter) {
              _StatusFilter.all => true,
              _StatusFilter.success => c.state == SamseerCallState.success,
              _StatusFilter.redirect => c.state == SamseerCallState.redirect,
              _StatusFilter.clientError =>
                c.state == SamseerCallState.clientError,
              _StatusFilter.serverError =>
                c.state == SamseerCallState.serverError,
              _StatusFilter.errors =>
                c.state == SamseerCallState.error || c.hasError,
            })
        .toList();
    return result;
  }
}
```

Remove the old `_apply` method from `_CallListScreenState` (it now lives in `_NetworkViewState`). Keep `_onMenu` on `_CallListScreenState` unchanged. The `_AnimatedTile`, `_SearchBar`, `_FilterRow`, and `_StatusFilter` enum stay where they are (file-private, shared).

- [ ] **Step 7: Run the full test suite**

Run: `cd /Users/airlangga/Documents/sandbox/samseer && flutter test`
Expected: PASS (all tests across all files).

- [ ] **Step 8: Analyze**

Run: `cd /Users/airlangga/Documents/sandbox/samseer && flutter analyze lib test`
Expected: No issues.

- [ ] **Step 9: Commit**

```bash
cd /Users/airlangga/Documents/sandbox/samseer
git add lib/src/ui/theme/samseer_theme.dart lib/src/ui/screen/console_view.dart lib/src/ui/screen/call_list_screen.dart test/console_filter_test.dart
git commit -m "feat: console tab with level/source filter capsules and detail view"
```

---

### Task 6: Example app, docs, version bump

**Files:**
- Modify: `example/lib/main.dart`
- Modify: `example/lib/samseer_webview_demo_page.dart`
- Modify: `README.md`
- Modify: `CHANGELOG.md`
- Modify: `pubspec.yaml`

**Interfaces:**
- Consumes: `Samseer.captureLogs`, the extended `webViewInterceptorScript`, the Console tab.
- Produces: a runnable manual-test surface and updated docs. No automated tests (demo/docs).

- [ ] **Step 1: Wrap example `runApp` in captureLogs and add an App-logs section**

In `example/lib/main.dart`, change the end of `main()`:

```dart
  samseerNotifications.start();

  samseer.captureLogs(() => runApp(const ExampleApp()));
}
```

Add a new section to the `Home` `ListView` children, after the `WebView` section's closing `]),` and before the final `],`:

```dart
          _Section(title: 'Console (App logs)', children: [
            _Tile(
              label: 'print() a string',
              onTap: () => print('Hello from the example app'),
            ),
            _Tile(
              label: 'debugPrint() a string',
              onTap: () => debugPrint('debugPrint line from example'),
            ),
            _Tile(
              label: 'print() a Map (readable, not [object Object])',
              onTap: () => print({
                'user': 1,
                'items': [1, 2, 3],
                'nested': {'ok': true},
              }),
            ),
            _Tile(
              label: 'Throw an uncaught async error',
              onTap: () => Future<void>.error(
                  StateError('deliberate example error')),
            ),
          ]),
```

`debugPrint` and `print` are in `package:flutter/material.dart` (already imported via `material.dart`). No new import needed.

- [ ] **Step 2: Add WebView console demo buttons**

In `example/lib/samseer_webview_demo_page.dart`, add buttons to the demo HTML. After the existing `<button onclick="doFetch404()">…</button>` line, insert:

```html
  <button onclick="console.log('plain log from webview')">console.log string</button>
  <button onclick="console.warn('heads up')">console.warn</button>
  <button onclick="console.error('something broke')">console.error</button>
  <button onclick="logObject()">console.log object + array</button>
  <button onclick="console.log('mixed', 42, true, {k:'v'})">console.log mixed args</button>
  <button onclick="boom()">throw uncaught error</button>
  <button onclick="rejectPromise()">unhandled promise rejection</button>
```

Add the matching JS functions inside the existing `<script>` block (after `doFetch404`):

```js
    function logObject() {
      console.log('an object:', { id: 1, tags: ['a', 'b'], ok: true }, [10, 20, 30]);
    }
    function boom() {
      throw new Error('deliberate webview error');
    }
    function rejectPromise() {
      Promise.reject(new Error('deliberate rejection'));
    }
```

- [ ] **Step 3: Update README**

In `README.md`, add a bullet to the Features list (after the WebView traffic bullet):

```markdown
- 🖥️ **Console capture** — WebView `console.*` + JS errors, and your Flutter app's `print`/`debugPrint`/uncaught errors, in one filterable Console tab (objects render as readable JSON, not `[object Object]`)
```

Add a Console section under the WebView integration section:

```markdown
### Console (App + WebView)

Samseer has a **Console** tab (bottom nav, next to Network) that collects:

- **WebView** — `console.log/info/warn/error/debug`, uncaught JS errors, and
  unhandled promise rejections. **No extra wiring** — it rides the same
  `webViewInterceptorScript` + `samseer_webview` handler you already set up for
  WebView traffic.
- **App (Dart)** — `print`, `debugPrint`, Flutter framework errors, and uncaught
  async errors. Wrap your `runApp` once:

  ```dart
  void main() {
    samseer.captureLogs(() => runApp(const MyApp()));
  }
  ```

Filter by level (Log/Info/Warn/Error/Debug) and source (App/WebView). Objects and
arrays are rendered as readable JSON instead of `[object Object]`.
```

- [ ] **Step 4: Update CHANGELOG and version**

In `pubspec.yaml`, change:

```yaml
version: 0.5.0
```

In `CHANGELOG.md`, add a new top entry:

```markdown
## 0.5.0

- feat: unified **Console** tab capturing WebView `console.*` + JS errors and
  Flutter-app `print`/`debugPrint`/uncaught errors, with level and source filter
  capsules and a detail view.
- feat: `Samseer.captureLogs(() => runApp(...))` to capture Dart-side logs.
- feat: WebView network errors are surfaced into the Console (configurable via
  `SamseerConfiguration.captureNetworkErrorsInConsole`).
- feat: readable console serialization — objects/arrays render as JSON instead
  of `[object Object]`.
- chore: `SamseerConfiguration.maxConsoleLogsCount` (default 500).
```

- [ ] **Step 5: Verify the package and example build**

Run: `cd /Users/airlangga/Documents/sandbox/samseer && flutter analyze && flutter test`
Expected: No analyzer issues; all tests pass.

Run: `cd /Users/airlangga/Documents/sandbox/samseer/example && flutter analyze`
Expected: No issues.

- [ ] **Step 6: Manual test (record result in commit)**

Run the example on a device/emulator. Verify:
1. Tap the App-logs tiles → open inspector → Console tab → entries appear with source `App`, the Map renders as readable JSON (not `[object Object]`), the async error appears as an Error entry.
2. Open WebView demo → tap console buttons → Console shows `WebView`-sourced entries; the object/array button renders readable JSON; throw/reject buttons produce Error entries; the 404 fetch produces a bridged `Network error` entry.
3. Filter capsules (level + source) and search narrow the list as expected.
4. The Console nav badge shows the live count.

- [ ] **Step 7: Commit**

```bash
cd /Users/airlangga/Documents/sandbox/samseer
git add example/lib/main.dart example/lib/samseer_webview_demo_page.dart README.md CHANGELOG.md pubspec.yaml
git commit -m "docs: demo console capture in example, README, changelog; bump to 0.5.0"
```

---

## Self-Review

**Spec coverage:**
- Data model (`SamseerConsoleLog`, level/source enums) → Task 1. ✓
- Storage second ring buffer + cap + clear/dispose → Task 1. ✓
- Config `maxConsoleLogsCount` + `captureNetworkErrorsInConsole` → Task 1. ✓
- WebView JS: console patching, `error`/`unhandledrejection`, `[object Object]` fix (circular-safe, never throws) → Task 4. ✓
- Dispatcher `log` branch + `data`/`stack` + level mapping → Task 2. ✓
- Network-error → Console bridging (errors only, configurable) → Task 2. ✓
- App-side `captureLogs` zone (print/debugPrint/FlutterError/PlatformDispatcher) → Task 3. ✓
- UI: bottom nav Network/Console with badge, console view, level + source capsules, tile, detail with JsonViewer + stack → Task 5. ✓
- Public API exports + `consoleLogs`/`consoleStream` getters → Tasks 1–2. ✓
- Example app updates (required deliverable) → Task 6. ✓
- README/CHANGELOG/version bump → Task 6. ✓

**Placeholder scan:** No TBD/TODO/"handle edge cases"; every code step shows complete code. ✓

**Type consistency:** `SamseerConsoleLog` ctor params, `samseerLogLevelFromString`, `addConsoleLog`, `consoleStream`/`consoleLogs`, `applyConsoleFilter` signature, `SamseerColors.forLogLevel`, and `ConsoleView`/`ConsoleDetailScreen` names are used identically across Tasks 1–6. The dispatcher emits `kind:'log'` with `level/message/data/stack`, matching `_onLog`'s reads and the JS `sendLog` payload. ✓
