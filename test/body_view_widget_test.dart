import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:samseer/src/core/samseer_configuration.dart';
import 'package:samseer/src/core/samseer_core.dart';
import 'package:samseer/src/feature/exporter.dart';
import 'package:samseer/src/model/http_body.dart';
import 'package:samseer/src/model/http_call.dart';
import 'package:samseer/src/model/http_request.dart';
import 'package:samseer/src/model/http_response.dart';
import 'package:samseer/src/ui/screen/call_detail_screen.dart';
import 'package:samseer/src/ui/text/body_document.dart';
import 'package:samseer/src/ui/text/body_rows.dart';
import 'package:samseer/src/ui/widget/binary_body_view.dart';
import 'package:samseer/src/ui/widget/body_text_sliver.dart';

// Builders are top level so the closures sent to the isolate capture only
// the body and content type.
BodyDocument Function() _bodyDoc(dynamic body, String? contentType) =>
    () => documentFromBody(body, contentType: contentType);

BodyDocument Function() _curlDoc(SamseerHttpCall call) =>
    () => documentFromText(Exporter.buildCurl(call), highlightJson: false);

List<Map<String, dynamic>> _bigList() => List.generate(
  20000,
  (i) => {
    'id': i,
    'name': 'item number $i',
    'email': 'user$i@example.com',
    'active': i.isEven,
    'score': i * 1.5,
  },
);

void main() {
  late SamseerCore core;
  final t = DateTime(2026, 11, 5, 13, 41, 6);

  setUp(() {
    core = SamseerCore(
      configuration: SamseerConfiguration(
        showInspectorOnShake: false,
        onSaveFile: (name, bytes) async => true,
      ),
    );
  });

  tearDown(() => core.dispose());

  SamseerHttpCall addCall({
    dynamic requestBody,
    String? requestContentType,
    SamseerHttpResponse? response,
  }) {
    final call = SamseerHttpCall(
      id: core.nextId(),
      method: 'POST',
      uri: 'https://example.com/api/items',
      endpoint: '/api/items',
      server: 'example.com',
      secure: true,
      client: 'Dio',
      createdAt: t,
      request: SamseerHttpRequest(
        time: t,
        body: requestBody,
        contentType: requestContentType,
      ),
      response: response,
    );
    core.addCall(call);
    return call;
  }

  SamseerHttpResponse jsonResponse(dynamic body) => SamseerHttpResponse(
    status: 200,
    time: t,
    body: body,
    contentType: 'application/json',
  );

  // The document is built in a background isolate. `compute` only completes
  // on the real event loop, so the cache entry the screen reads is filled
  // here first; the screen then gets the same, already completed Future.
  Future<void> warm(
    WidgetTester tester,
    Object owner,
    String slot,
    BodyDocument Function() build,
  ) async {
    await tester.runAsync(() => loadBodyDocument(owner, slot, build));
  }

  // Lets the real event loop deliver completed isolate results to the
  // FutureBuilder, then rebuilds.
  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
  }

  Future<void> openTab(WidgetTester tester, int callId, String tab) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CallDetailScreen(core: core, callId: callId),
      ),
    );
    await tester.tap(find.text(tab));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    await settle(tester);
  }

  testWidgets('large json response renders lazily', (tester) async {
    final response = jsonResponse(_bigList());
    final call = addCall(response: response);
    await warm(
      tester,
      response,
      'body',
      _bodyDoc(response.body, response.contentType),
    );

    await openTab(tester, call.id, 'Response');

    final rows = find.byType(BodyRowView).evaluate().length;
    expect(rows, greaterThan(0));
    expect(rows, lessThan(300));
    expect(find.textContaining('Download .txt'), findsOneWidget);
  });

  testWidgets('large body has a draggable scrollbar', (tester) async {
    final response = jsonResponse(_bigList());
    final call = addCall(response: response);
    await warm(
      tester,
      response,
      'body',
      _bodyDoc(response.body, response.contentType),
    );

    await openTab(tester, call.id, 'Response');

    final bar = find.ancestor(
      of: find.byType(CustomScrollView),
      matching: find.byType(Scrollbar),
    );
    expect(bar, findsOneWidget);
    final scrollbar = tester.widget<Scrollbar>(bar);
    expect(scrollbar.interactive, isTrue);
    expect(scrollbar.controller, isNotNull);
    expect(
      tester.widget<CustomScrollView>(find.byType(CustomScrollView)).controller,
      same(scrollbar.controller),
    );
  });

  testWidgets('small json response shows copy', (tester) async {
    final response = jsonResponse({'ok': true});
    final call = addCall(response: response);
    await warm(
      tester,
      response,
      'body',
      _bodyDoc(response.body, response.contentType),
    );

    await openTab(tester, call.id, 'Response');

    expect(find.text('Copy Response Body'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(BodyRowView),
        matching: find.textContaining('"ok"'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('pending then response arrives', (tester) async {
    final call = addCall();
    final response = jsonResponse({'ok': true});
    await warm(
      tester,
      response,
      'body',
      _bodyDoc(response.body, response.contentType),
    );

    await openTab(tester, call.id, 'Response');
    // Pending (no response, no error) keeps the existing loading state.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(BodyRowView), findsNothing);

    core.addResponse(call.id, response);
    await tester.pump();
    await tester.pump();
    await settle(tester);

    expect(
      find.descendant(
        of: find.byType(BodyRowView),
        matching: find.textContaining('"ok"'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('curl tab is virtualized', (tester) async {
    final call = addCall(
      requestBody: jsonEncode(_bigList()),
      requestContentType: 'application/json',
    );
    expect(
      utf8.encode(call.request.body as String).length,
      greaterThan(1024 * 1024),
    );
    await warm(tester, call.request, 'curl', _curlDoc(call));

    await openTab(tester, call.id, 'cURL');

    final rows = find.byType(BodyRowView).evaluate().length;
    expect(rows, greaterThan(0));
    expect(rows, lessThan(300));
    expect(find.textContaining('Download .txt'), findsOneWidget);
  });

  testWidgets('binary body keeps the old viewer', (tester) async {
    final response = SamseerHttpResponse(
      status: 200,
      time: t,
      body: SamseerBinaryBody(
        totalSize: 4,
        bytes: Uint8List.fromList([1, 2, 3, 4]),
        contentType: 'application/octet-stream',
      ),
      contentType: 'application/octet-stream',
    );
    final call = addCall(response: response);

    await openTab(tester, call.id, 'Response');

    expect(find.byType(BodyRowView), findsNothing);
    expect(find.byType(BinaryBodyView), findsOneWidget);
    expect(find.text('Copy Response Body'), findsOneWidget);
  });

  // Selects everything under the screen's SelectionArea and returns what
  // "Copy" puts on the clipboard.
  Future<String> copyAll(WidgetTester tester) async {
    final clipboard = <String>[];
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        clipboard.add((call.arguments as Map)['text'] as String);
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    // Selectables register on the frame after they are built.
    await tester.pump();
    final inside = tester.element(find.byType(CustomScrollView));
    Actions.invoke(
      inside,
      const SelectAllTextIntent(SelectionChangedCause.keyboard),
    );
    await tester.pump();
    Actions.invoke(inside, CopySelectionTextIntent.copy);
    await tester.pump();
    expect(clipboard, isNotEmpty);
    return clipboard.last;
  }

  testWidgets('selection copy keeps line breaks, joins continuation rows', (
    tester,
  ) async {
    const text = 'abcdefghij\n\nxy\r\nlast';
    final doc = BodyDocument(
      text: text,
      rows: buildRows(text, highlightJson: false, chunkSize: 4),
      byteLength: text.length,
    );
    expect(doc.rows.length, 6);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SelectionArea(
            child: CustomScrollView(slivers: [BodyTextSliver(document: doc)]),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(await copyAll(tester), 'abcdefghij\n\nxy\nlast');
  });

  testWidgets('select all and copy in the response tab keeps lines', (
    tester,
  ) async {
    final response = jsonResponse({
      'a': 1,
      'b': [true, null],
    });
    final call = addCall(response: response);
    await warm(
      tester,
      response,
      'body',
      _bodyDoc(response.body, response.contentType),
    );

    await openTab(tester, call.id, 'Response');

    expect(await copyAll(tester), contains(Exporter.formatBody(response.body)));
  });
}
