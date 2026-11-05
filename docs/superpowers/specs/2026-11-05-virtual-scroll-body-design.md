# Virtual scroll for request/response bodies + download as .txt

Date: 2026-11-05. Target: PR from `AIRGG/samseer` (fork) to `samueljiwandono0310/samseer:master`.

## Intent

Airlangga uses Samseer while developing apps on Android and iOS. Large JSON
responses (around 2 MB, and even ~500 KB) are captured by the interceptors
without problems, but opening the call's **Response** tab makes the app crash.
Today `JsonViewer` (`lib/src/ui/widget/json_viewer.dart`) renders the whole body
as one `SelectableText.rich` with every token as a span, laid out at once inside
a plain `ListView` in `call_detail_screen.dart`. That is the cause.

What he does in that tab: scrolls and reads the body field by field, value by
value, and copies the body to write API documentation. When the body is too big
to copy, he wants it saved as a plain `.txt` file instead.

## Goals

1. Opening the Request, Response, or cURL tab with a large text body (500 KB, 2 MB, and
   comfortably beyond) never crashes and scrolls smoothly.
2. JSON still looks the way it does now: pretty-printed, indented, syntax-colored.
   It is split into lines and only the lines on screen are built (virtual
   scrolling). Line numbers in a left gutter.
3. Copy rule, per body:
   - body text ≤ **100 KB** (decided by Airlangga): the existing **Copy** button
     works as today.
   - body text > 100 KB: the Copy button is replaced by **Download .txt**.
4. Download .txt saves the exact text Copy would have produced:
   - **Android**: written straight into the public **Downloads** folder, then a
     `SamseerToast` with the file name.
   - **iOS**: there is no Downloads folder, so the system "Save to Files" dialog
     opens and the user picks the place.
5. Works for both request and response bodies; the response is the main case.

## Non-goals

- Collapsing/expanding JSON nodes.
- Search/find inside a body.
- Changing the binary (image/PDF/octet-stream), multipart, or CSV viewers.
- Sharing to other apps (AirDrop, WhatsApp, Drive). Saving to Downloads is enough
  for now.
- Changing how bodies are captured or stored.

## Anti-goals

- A "fix" that still freezes or crashes on 500 KB because formatting/parsing of
  the body runs on the UI thread in one go. Large-body work must not block the
  first frame of the tab.
- JSON that looks worse than today (lost colors, lost indentation).

## Decisions

Airlangga decided:
- Virtual scroll for bodies, response first, request too.
- Copy limit is 100 KB; above it, Download .txt replaces Copy.
- The file is a plain `.txt`, saved to Downloads.
- Both Android and iOS.
- A file-saving package **is added as a direct dependency of Samseer** (no bridge
  pattern), so Download works without any setup in the host app. This is a new
  dependency in a package that advertises "no extra packages", so the README and
  CHANGELOG must say so.

Claude's calls (can be overridden):
- Virtual scroll applies to every body rendered as text: JSON, XML,
  form-urlencoded map, plain text, HTML. Binary/multipart/CSV views stay as they are.
- The 100 KB rule also applies to the other copy actions that carry a body and
  can get just as big: the call dump copy in the detail screen's menu, Copy cURL,
  and the list screen's "Copy as JSON" export of all calls. Each of those offers
  Download .txt above 100 KB instead of Copy.
- Size is measured on the text that would be copied (UTF-8 length), not on the
  captured `size` field.
- The existing "Copied, large content" warning toast for >1 MB becomes
  unnecessary for bodies, since copying is now capped at 100 KB.
- File name: `samseer-<method>-<endpoint-slug>-<request|response>-<timestamp>.txt`
  (builder may simplify).
- **One source of truth for text.** The viewer renders exactly the text that
  Copy/Download produces (`Exporter.buildRequestBody` / `buildResponseBody`),
  split into lines and colored per line. Gutter line N is line N of the
  downloaded `.txt`, which matters for writing API docs. JSON is pretty-printed
  with 2-space indent before splitting; colors and indentation stay as today.
  Side effect: a form-urlencoded body shows as the `a=b&c=d` text it copies as,
  no longer as a JSON tree.
- **Very long lines** (minified HTML, one-line text, a JSON string holding
  hundreds of KB of base64): lines wrap as today, but any source line longer
  than a fixed chunk size (builder picks, a few thousand chars) is split into
  continuation rows. Continuation rows have no line number, so the gutter still
  counts source lines. No single row is ever big enough to freeze the tab.
- **cURL tab is in scope.** `_CurlTab` puts the whole cURL (with the full
  request body) in one `SelectableText` and would crash the same way. It uses
  the same virtualized viewer as plain text (no JSON coloring), built off the
  UI thread for big bodies.
- **Android 9 and below** (no MediaStore): no extra permission is asked of the
  host app. The file is saved to the app-specific external files folder
  instead, and the toast shows that path. Android 10+ saves to public
  Downloads as in the goals.

## Constraints

- Dart/Flutter package, `sdk: ^3.5.0`, `flutter: ">=3.19.0"`, Material 3,
  dark-mode inspector only (`SamseerTheme`).
- Follow existing patterns: `SamseerToast` for feedback, `Exporter` for building
  the text, `SamseerTheme.mono` for monospace.
- Android: saving to Downloads on Android 10+ needs MediaStore (or the package
  that wraps it); must not require the host app to add storage permissions on
  modern Android if avoidable. Document any manifest/Info.plist step the chosen
  package needs, both in README and in the example app.
- Tests on this machine: one full `flutter test --concurrency=1` at the end.

## Left to the builder

- Which file-saving package (must support Android Downloads + iOS save dialog,
  maintained, compatible with the SDK floors above).
- How lines are produced (pretty-print to lines, then color each line) and
  whether that runs in an isolate (`compute`) for big bodies, with a short
  loading state.
- How the body list is combined with the Headers/Query sections in one scroll
  view (e.g. `CustomScrollView` + slivers) so the body is truly lazy.
- Text selection inside the virtualized body (whole-document selection across
  lines is not expected to survive virtualization).
- Whether the Console detail view (which also uses `JsonViewer`) picks up the
  new viewer.
- Tests: line-splitting/formatting logic, the 100 KB threshold switch, file
  name building. Saving itself can be behind a small seam so it is testable.
