# Virtual-Scrolled Bodies + Download .txt Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Opening the Request, Response or cURL tab with a 500 KB to 2 MB+ text body never crashes; JSON stays pretty and colored but only visible lines are built; any copy of more than 100 KB becomes "Download .txt" through the system save dialog.

**Architecture:** A pure-Dart layer turns a body into a `BodyDocument` (the exact text Copy/Download produces, split into numbered rows of colored tokens, long lines chunked). It is built off the UI thread with `compute` and cached per request/response object so detail-screen rebuilds never redo it. A `BodyTextSliver` renders the rows lazily inside a `CustomScrollView`. A small export helper decides Copy vs Download by UTF-8 size and saves via `file_picker`'s `FilePicker.saveFile`.

**Tech Stack:** Dart/Flutter (Material 3, slivers, `compute`), `file_picker` ^13.3.2, `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-11-05-virtual-scroll-body-design.md`

## Global Constraints

- Copy limit: **100 KB = 102400 bytes of UTF-8**. `<= 102400` → Copy to clipboard; `> 102400` → Download .txt.
- Viewer text == copied/downloaded text (single source: `Exporter.formatBody`). Gutter line N == line N of the `.txt`.
- JSON keeps today's look: 2-space indent, colors from `_SyntaxColors` in `json_viewer.dart` (key = `cs.primary` bold, string `0xFF22C55E`, number `0xFFF59E0B`, bool `0xFFEC4899`, null = `cs.onSurfaceVariant`, brackets = `cs.onSurface`, punctuation = `cs.onSurfaceVariant`).
- Long lines split into continuation rows of at most `kRowChunkSize = 2000` chars; continuation rows have no line number.
- New dependency `file_picker: ^13.3.2` (static `FilePicker.saveFile(fileName:, bytes:, mimeType:) → Future<Uri?>`, null = cancelled). Environment in `pubspec.yaml` AND `example/pubspec.yaml`: `sdk: ^3.10.0`, `flutter: ">=3.38.0"`.
- No storage permission, manifest or Info.plist changes expected; verify on `flutter pub get` + example build, and document whatever `file_picker` turns out to need.
- Binary, multipart and CSV bodies keep their current viewers (`BodyViewer`). Console's `JsonViewer` use is unchanged.
- Dark-mode inspector only (`SamseerTheme.theme()`), feedback via `SamseerToast`, mono text via `SamseerTheme.mono(context)`.
- **Test cadence (user rule for this Mac, overrides per-step runs):** write the tests in each task, do not run them per task; one `flutter analyze` + one `flutter test --concurrency=1` in Task 5, then fix failures in a batch and rerun only the failed files.
- This ships in the same release as the Console feature on this branch: CHANGELOG `## 0.6.0`, no new version bump.
- No em/en dashes in new user-facing strings or docs.

## Review Focus

1. Response arrives while the Response tab is already open (pending → done): the body must appear (cache keyed on the response object, not the call id). Test in Task 4.
2. Other calls stream in while a big body is open (detail screen rebuilds on every storage emit): the document must not be rebuilt. Test in Task 2 (same future for same owner).
3. A single 500 KB line (minified JSON or base64 string value): no row longer than 2000 chars, text concatenation unchanged. Test in Task 1.
4. CRLF bodies (`\r\n`) and empty-string bodies: no stray `\r` in rows; empty text yields one empty numbered row, not a crash. Test in Task 1.
5. User cancels the save dialog, or saving throws: cancel = no toast, throw = error toast, clipboard untouched in both. Test in Task 3.

---

### Task 1: Rows and JSON tokenizer (pure Dart)

**Files:**
- Create: `lib/src/ui/text/body_rows.dart`
- Test: `test/body_rows_test.dart`

**Interfaces:**
- Produces:
  - `enum BodyTokenKind { plain, key, string, number, boolean, nullValue, bracket, punct }`
  - `class BodyToken { const BodyToken(this.kind, this.text); final BodyTokenKind kind; final String text; }`
  - `class BodyRow { const BodyRow({this.lineNumber, required this.tokens}); final int? lineNumber; final List<BodyToken> tokens; String get text; }` (`lineNumber` null = continuation row; `text` = tokens joined)
  - `const int kRowChunkSize = 2000;`
  - `List<BodyToken> tokenizeJsonLine(String line)`
  - `List<BodyRow> buildRows(String text, {required bool highlightJson, int chunkSize = kRowChunkSize})`

- [ ] **Step 1: Write the tests** in `test/body_rows_test.dart`:
  - `numbers source lines from 1`: `buildRows('a\nb\nc', highlightJson: false)` → 3 rows, `lineNumber` 1,2,3, texts `a`,`b`,`c`.
  - `strips CR from CRLF`: `buildRows('a\r\nb', ...)` → texts `a`,`b`, no row text contains `\r`.
  - `empty text gives one empty row`: `buildRows('', ...)` → 1 row, `lineNumber` 1, text `''`.
  - `chunks long lines into continuation rows`: a 5000-char line with `chunkSize: 2000` → 3 rows, lineNumbers `[1, null, null]`, every row text length ≤ 2000, joined text == original.
  - `500 KB single line stays bounded`: `'x' * 500000` → all rows ≤ 2000 chars, row count 250.
  - `tokenizes key vs string value`: `tokenizeJsonLine('  "id": "abc",')` → kinds in order `plain('  ')`, `key('"id"')`, `punct(': ')` (or `punct(':')` + `plain(' ')`, either is fine as long as joined text matches), `string('"abc"')`, `punct(',')`; assert by filtering out plain/punct: `[key "id", string "abc"]` with quotes included.
  - `tokenizes number, bool, null, brackets`: `'  "n": 1.5e3, "b": true, "z": null, "a": [{}]'` → contains tokens `number '1.5e3'`, `boolean 'true'`, `nullValue 'null'`, `bracket '['`, `bracket '{'`, `bracket '}'`, `bracket ']'`.
  - `escaped quotes stay inside the string`: `'"k": "a\\"b"'` → one `string` token `"a\"b"`.
  - `highlighted chunks keep token kinds`: a JSON line `"k": "` + `'y' * 4500` + `"` with `highlightJson: true` → continuation rows' tokens are `string` kind; joined text of all rows == original line.
  - `plain mode makes one plain token per row`: `buildRows('{"a":1}', highlightJson: false)` → single token, kind `plain`.

- [ ] **Step 2: Implement** `lib/src/ui/text/body_rows.dart`. No Flutter imports (must run inside `compute`). Tokenizer is a single left-to-right scan: a `"…"` run (honoring backslash escapes) is a `key` when the next non-space char after it is `:`, else `string`; `-?digits[.digits][e±digits]` → `number`; `true|false` → `boolean`; `null` → `nullValue`; `{}[]` → `bracket`; `,:` → `punct`; everything else (indent, spaces) → `plain`. An unterminated string runs to end of line as `string`. Chunking slices the full line's token list at chunk boundaries, splitting a token in two when it straddles a boundary (both halves keep the kind).

- [ ] **Step 3: Commit**

```bash
git add lib/src/ui/text/body_rows.dart test/body_rows_test.dart
git commit -m "feat: line rows and json tokenizer for virtualized bodies"
```

---

### Task 2: BodyDocument, public formatBody, cached off-thread loading

**Files:**
- Create: `lib/src/ui/text/body_document.dart`
- Modify: `lib/src/feature/exporter.dart` (rename `_formatBody` → public `static String formatBody(dynamic body, {String? contentType})` using a 2-space `JsonEncoder` internally; `buildRequestBody`/`buildResponseBody` call it; behavior unchanged)
- Test: `test/body_document_test.dart`

**Interfaces:**
- Consumes: Task 1 `buildRows`, `BodyRow`.
- Produces:
  - `class BodyDocument { const BodyDocument({required this.text, required this.rows, required this.byteLength}); final String text; final List<BodyRow> rows; final int byteLength; int get lineCount; }` (`byteLength` = `utf8.encode(text).length`; `lineCount` = number of rows with a non-null `lineNumber`)
  - `BodyDocument documentFromText(String text, {required bool highlightJson})`
  - `BodyDocument documentFromBody(dynamic body, {String? contentType})` → text = `Exporter.formatBody(body, contentType: contentType)`; `highlightJson` = trimmed text starts with `{` or `[`.
  - `bool usesTextViewer(dynamic body, String? contentType)` → false for `SamseerBinaryBody`, `SamseerMultipartBody`, and `String` bodies classified `SamseerBodyKind.csv`; true otherwise (JSON, XML, form map, text, HTML).
  - `Future<BodyDocument> loadBodyDocument(Object owner, String slot, BodyDocument Function() build)` → runs `build` via `compute((_) => build(), null)` and caches the future in an `Expando<Map<String, Future<BodyDocument>>>` keyed on `owner` (a `SamseerHttpRequest`, `SamseerHttpResponse` or `SamseerHttpCall` instance) and `slot` (`'body'` or `'curl'`). Same owner + slot → the identical `Future` instance.

- [ ] **Step 1: Write the tests** in `test/body_document_test.dart`:
  - `json map renders as pretty 2-space json`: `documentFromBody({'a': 1, 'b': [true]})` → `text` == `JsonEncoder.withIndent('  ').convert(...)`, rows' texts joined with `\n` == `text`, `lineCount` == text line count.
  - `text equals Exporter copy text`: for a `SamseerHttpCall` with a JSON string response body, `documentFromBody(body, contentType: 'application/json').text == Exporter.buildResponseBody(call)`.
  - `form-urlencoded map shows as a=b&c=d`: `documentFromBody({'a': '1', 'c': 'd'}, contentType: 'application/x-www-form-urlencoded').text` == `'a=1&c=d'`.
  - `byteLength counts utf8 bytes`: `documentFromText('é', highlightJson: false).byteLength` == 2.
  - `usesTextViewer routes`: false for `SamseerBinaryBody`, `SamseerMultipartBody`, `('a,b', 'text/csv')`; true for Map, JSON string, `('<a/>', 'application/xml')`.
  - `cache returns the same future for the same owner and slot` (wrap in `tester.runAsync` or a plain `test` with `TestWidgetsFlutterBinding.ensureInitialized()`): two calls with the same `SamseerHttpResponse` instance and `'body'` → `identical(f1, f2)`; a different `SamseerHttpResponse` instance → not identical; awaited result has expected text.

- [ ] **Step 2: Implement** `exporter.dart` change and `body_document.dart` per Interfaces.

- [ ] **Step 3: Commit**

```bash
git add lib/src/ui/text/body_document.dart lib/src/feature/exporter.dart test/body_document_test.dart
git commit -m "feat: cached off-thread body documents shared by viewer and copy"
```

---

### Task 3: Copy-or-download export helper + `file_picker`

**Files:**
- Create: `lib/src/feature/text_export.dart`
- Create: `lib/src/ui/widget/export_text_button.dart`
- Modify: `pubspec.yaml` (add `file_picker: ^13.3.2` under `# Features`; environment `sdk: ^3.10.0`, `flutter: ">=3.38.0"`), `example/pubspec.yaml` (same environment)
- Test: `test/text_export_test.dart`

**Interfaces:**
- Produces:
  - `const int kCopyLimitBytes = 100 * 1024;`
  - `bool exceedsCopyLimit(int utf8Bytes)` → `utf8Bytes > kCopyLimitBytes`
  - `String buildExportFileName({required String part, String? method, String? endpoint, required DateTime time})` → `samseer[-<method lower>][-<endpoint slug>]-<part>-<yyyyMMdd-HHmmss>.txt`; slug = endpoint lowercased, runs of non `[a-z0-9]` → `-`, trimmed of `-`, max 40 chars; `part` ∈ `request|response|curl|call|calls`.
  - `typedef TextFileSaver = Future<bool> Function(String fileName, Uint8List bytes);` (true = saved, false = cancelled)
  - `class SamseerTextExport { static TextFileSaver saver = _filePickerSaver; }` where `_filePickerSaver` calls `FilePicker.saveFile(fileName: fileName, bytes: bytes, mimeType: 'text/plain')` and returns `uri != null`. Tests replace `saver`.
  - `Future<void> copyOrDownloadText(BuildContext context, {required String text, required String fileName, required String copiedTitle})`:
    - `<= limit`: `Clipboard.setData`, then success toast `copiedTitle` with subtitle `Exporter.formatSize(bytes)`.
    - `> limit`: `saver(fileName, utf8.encode(text))`; saved → success toast `Saved <fileName>`; cancelled → nothing; throws → error toast `Could not save file` with the error as subtitle. Clipboard never touched.
  - `class ExportTextButton extends StatelessWidget` ctor `({required String copyLabel, required BodyDocument? document, required String fileName, required String copiedTitle})`: `document == null` → disabled button showing `copyLabel`; `exceedsCopyLimit(document.byteLength)` → icon `Icons.download` and label `Download .txt (<size>)`; else icon `Icons.copy` and `copyLabel`. Tap → `copyOrDownloadText`.

- [ ] **Step 1: Write the tests** in `test/text_export_test.dart`:
  - `limit boundary`: `exceedsCopyLimit(102400)` false, `exceedsCopyLimit(102401)` true.
  - `file name`: `buildExportFileName(part: 'response', method: 'GET', endpoint: '/api/v1/Orders?x=1', time: DateTime(2026, 11, 5, 13, 41, 6))` == `'samseer-get-api-v1-orders-x-1-response-20261105-134106.txt'`; with only `part: 'calls'` → `'samseer-calls-20261105-134106.txt'`.
  - Widget tests (pump `MaterialApp(theme: SamseerTheme.theme(), home: Scaffold(body: ExportTextButton(...)))`, mock clipboard via `TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, …)` recording `Clipboard.setData`):
    - `small body copies`: 10-byte document → finds `copyLabel`, tap → clipboard got the text, saver not called.
    - `large body downloads`: 102401-byte document → finds text starting `Download .txt`, tap → fake saver called once with `fileName` and bytes == `utf8.encode(text)`, clipboard not called, toast `Saved <fileName>` shown.
    - `cancel does nothing`: fake saver returns false → no `Saved` text, clipboard not called.
    - `save error shows error toast`: fake saver throws → finds `Could not save file`.
    - `loading document disables the button`: `document: null` → button `onPressed` is null.
  - `tearDown` restores `SamseerTextExport.saver` and clears the mock handler.

- [ ] **Step 2: Implement** per Interfaces; run `flutter pub get` in root and `example/` and confirm `file_picker` resolves and `FilePicker.saveFile` exists with that signature (adjust the call, not the seam, if the 13.x API differs).

- [ ] **Step 3: Commit**

```bash
git add pubspec.yaml pubspec.lock example/pubspec.yaml example/pubspec.lock lib/src/feature/text_export.dart lib/src/ui/widget/export_text_button.dart test/text_export_test.dart
git commit -m "feat: copy-or-download export with 100 KB limit via file_picker"
```

---

### Task 4: Virtualized body sliver + detail and list screens

**Files:**
- Create: `lib/src/ui/widget/body_text_sliver.dart`
- Modify: `lib/src/ui/widget/json_viewer.dart` (make `_SyntaxColors` public as `SamseerSyntaxColors` so the sliver reuses the exact colors)
- Modify: `lib/src/ui/screen/call_detail_screen.dart` (`_RequestTab`, `_ResponseTab`, `_CurlTab`, `_copyDump`)
- Modify: `lib/src/ui/screen/call_list_screen.dart` (`_onMenu` `'export'`)
- Test: `test/body_view_widget_test.dart`

**Interfaces:**
- Consumes: Task 2 `loadBodyDocument`, `documentFromBody`, `documentFromText`, `usesTextViewer`, `BodyDocument`; Task 3 `ExportTextButton`, `copyOrDownloadText`, `buildExportFileName`.
- Produces:
  - `class BodyTextSliver extends StatelessWidget` ctor `({required BodyDocument document})`: returns a `SliverList` (builder delegate, `itemCount = rows.length`) of `BodyRowView`.
  - `class BodyRowView extends StatelessWidget` ctor `({required BodyRow row, required int gutterDigits})`: gutter `Text` (line number right-aligned, width fits `gutterDigits`, empty for continuation rows, `cs.onSurfaceVariant`), then `Expanded(Text.rich(...))` with `SamseerTheme.mono(context)` and token colors from `SamseerSyntaxColors`.

- [ ] **Step 1: Write the tests** in `test/body_view_widget_test.dart` (build a `SamseerCore`, add a `SamseerHttpCall`, pump `CallDetailScreen(core:, callId:)` inside `MaterialApp`; use `tester.runAsync` around pumping/settling so `compute` completes; select tabs by tapping `Tab` text):
  - `large json response renders lazily`: response body = a list of 20000 maps (≈2 MB as JSON) → after load, `find.byType(BodyRowView)` count is > 0 and < 300, and `Download .txt` is shown.
  - `small json response shows copy`: `{'ok': true}` → finds `Copy Response Body`, rows show `"ok"` text.
  - `pending then response arrives`: open Response tab while `response == null` (shows the existing "No response received" state) → `core.addResponse(id, …)` → after load, a `BodyRowView` with `"ok"` exists.
  - `curl tab is virtualized`: request body 2 MB JSON string → cURL tab shows `BodyRowView`s (< 300) and `Download .txt`.
  - `binary body keeps the old viewer`: response body `SamseerBinaryBody` → `find.byType(BodyRowView)` is empty and `BinaryBodyView` is found.

- [ ] **Step 2: Rebuild the three tabs** as `SelectionArea(child: CustomScrollView(slivers: [...]))`:
  - Request: Headers and Query Parameters `_Section`s as `SliverToBoxAdapter`; Body title (`BODY · <lineCount> lines` once loaded); then: `body == null` → "No body"; `!usesTextViewer(body, contentType)` → `SliverToBoxAdapter(BodyViewer(...))` as today; else `FutureBuilder` on `loadBodyDocument(call.request, 'body', () => documentFromBody(body, contentType: …))` → `SliverToBoxAdapter(LinearProgressIndicator)` while loading, `BodyTextSliver` when done (wrapped in `SliverPadding` + `DecoratedSliver` with the same `surfaceContainerHigh` rounded box `_Section` uses). Last: `SliverToBoxAdapter(ExportTextButton(copyLabel: 'Copy Request Body', fileName: buildExportFileName(part: 'request', …), copiedTitle: 'Request body copied', document: <loaded or null>))`. For non-text bodies keep the existing Copy button behavior but route it through `copyOrDownloadText`.
  - Response: same shape keyed on `call.response` (owner) with `'Copy Response Body'` / `'Response body copied'` / part `response`; keep the existing error/pending states.
  - cURL: owner `call.request`, slot `'curl'`, build `() => documentFromText(Exporter.buildCurl(call), highlightJson: false)`; button `'Copy cURL'` / `'cURL copied'` / part `curl`.
- [ ] **Step 3: Route `_copyDump`** (part `call`) **and the list's `'export'` menu** (part `calls`) through `copyOrDownloadText`, removing their old ">1 MB, may truncate" warning branches; keep the existing "Nothing to export" warning.

- [ ] **Step 4: Commit**

```bash
git add lib/src/ui/widget/body_text_sliver.dart lib/src/ui/widget/json_viewer.dart lib/src/ui/screen/call_detail_screen.dart lib/src/ui/screen/call_list_screen.dart test/body_view_widget_test.dart
git commit -m "feat: virtual-scrolled request, response and curl bodies"
```

---

### Task 5: Docs, example, and the single verification run

**Files:**
- Modify: `README.md` (Features bullet for large bodies + Download .txt; note the new `file_picker` dependency and the Flutter `>=3.38` floor, and any platform setup found in Task 3)
- Modify: `CHANGELOG.md` (add bullets to the existing `## 0.6.0` entry, same `* New:` style)
- Modify: `example/lib/main.dart` (in the `Dio` section add tiles `GET /comments (~160 KB, Download)` → `https://jsonplaceholder.typicode.com/comments` and `GET /photos (~1 MB)` → `https://jsonplaceholder.typicode.com/photos`)

- [ ] **Step 1: Write the docs and example tiles.** CHANGELOG bullets:
  - `* New: request, response and cURL bodies are virtual-scrolled with line numbers, so multi-MB JSON opens without freezing or crashing.`
  - `* New: copies over 100 KB become "Download .txt" through the system save dialog (Android "Save to", iOS "Save to Files").`
  - `* Changed: adds the \`file_picker\` dependency; minimum Flutter is now 3.38 (Dart 3.10).`
- [ ] **Step 2: Verify (the one batch run).**

Run: `pgrep -fl "flutter_tester|flutter test"` (must be empty), then `flutter analyze`, `(cd example && flutter analyze)`, `flutter test --concurrency=1 > <log> 2>&1; tail <log>`
Expected: no analyzer issues in either; `All tests passed!`. On failures: fix all in one batch, rerun only the failing files with `--concurrency=1`.

- [ ] **Step 3: Commit**

```bash
git add README.md CHANGELOG.md example/lib/main.dart
git commit -m "docs: document virtual-scrolled bodies and .txt download"
```

- [ ] **Step 4: Manual check on device (record result in the PR description)**

Android and iOS: Dio → `GET /photos` → Response tab opens quickly, scrolls smoothly, line numbers match; `Download .txt` → Android "Save to" screen → pick Downloads → toast `Saved …`; the file's line 100 matches gutter line 100. iOS → "Save to Files". `GET /comments` also downloads; `GET /posts/1` copies.
