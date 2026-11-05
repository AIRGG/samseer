import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
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
      configuration: const SamseerConfiguration(showInspectorOnShake: false),
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
}
