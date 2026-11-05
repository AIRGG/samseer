import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:samseer/src/feature/exporter.dart';
import 'package:samseer/src/model/http_body.dart';
import 'package:samseer/src/model/http_call.dart';
import 'package:samseer/src/model/http_request.dart';
import 'package:samseer/src/model/http_response.dart';
import 'package:samseer/src/ui/text/body_document.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('json map renders as pretty 2-space json', () {
    final body = {
      'a': 1,
      'b': [true],
    };
    final doc = documentFromBody(body);
    final expected = const JsonEncoder.withIndent('  ').convert(body);
    expect(doc.text, expected);
    expect(doc.rows.map((r) => r.text).join('\n'), expected);
    expect(doc.lineCount, expected.split('\n').length);
  });

  test('text equals Exporter copy text', () {
    final now = DateTime.now();
    final response = SamseerHttpResponse(
      status: 200,
      time: now,
      body: '{"a":1,"b":[2,3]}',
      contentType: 'application/json',
    );
    final call = SamseerHttpCall(
      id: 1,
      method: 'GET',
      uri: 'https://example.com/x',
      endpoint: '/x',
      server: 'example.com',
      secure: true,
      client: 'test',
      createdAt: now,
      request: SamseerHttpRequest(time: now),
      response: response,
    );
    expect(
      documentFromBody(response.body, contentType: 'application/json').text,
      Exporter.buildResponseBody(call),
    );
  });

  test('form-urlencoded map shows as a=b&c=d', () {
    final doc = documentFromBody(
      {'a': '1', 'c': 'd'},
      contentType: 'application/x-www-form-urlencoded',
    );
    expect(doc.text, 'a=1&c=d');
  });

  test('byteLength counts utf8 bytes', () {
    expect(documentFromText('é', highlightJson: false).byteLength, 2);
  });

  test('usesTextViewer routes', () {
    expect(usesTextViewer(const SamseerBinaryBody(totalSize: 1), null), false);
    expect(usesTextViewer(const SamseerMultipartBody(), null), false);
    expect(usesTextViewer('a,b', 'text/csv'), false);
    expect(usesTextViewer({'a': 1}, null), true);
    expect(usesTextViewer('{"a":1}', 'application/json'), true);
    expect(usesTextViewer('<a/>', 'application/xml'), true);
  });

  test('cache returns the same future for the same owner and slot', () async {
    final now = DateTime.now();
    final a = SamseerHttpResponse(status: 200, time: now, body: 'hi');
    final b = SamseerHttpResponse(status: 200, time: now, body: 'hi');
    final f1 = loadBodyDocument(a, 'body', () => documentFromBody('hi'));
    final f2 = loadBodyDocument(a, 'body', () => documentFromBody('other'));
    final f3 = loadBodyDocument(b, 'body', () => documentFromBody('hi'));
    expect(identical(f1, f2), isTrue);
    expect(identical(f1, f3), isFalse);
    expect((await f1).text, 'hi');
  });
  test('cache keeps the 5 most recent owners', () async {
    final now = DateTime.now();
    final owners = List.generate(
      6,
      (_) => SamseerHttpResponse(status: 200, time: now, body: 'hi'),
    );
    final first = [
      for (final o in owners.take(5))
        loadBodyDocument(o, 'body', () => documentFromBody('hi')),
    ];
    // Touch owner 2 so it is the most recent before the 6th arrives.
    expect(
      identical(
        loadBodyDocument(owners[1], 'body', () => documentFromBody('x')),
        first[1],
      ),
      isTrue,
    );
    loadBodyDocument(owners[5], 'body', () => documentFromBody('hi'));
    final again = loadBodyDocument(
      owners[0],
      'body',
      () => documentFromBody('hi'),
    );
    expect(identical(again, first[0]), isFalse);
    expect(
      identical(
        loadBodyDocument(owners[1], 'body', () => documentFromBody('x')),
        first[1],
      ),
      isTrue,
    );
    await Future.wait([...first, again]);
  });

  test('line count is cached on the rows', () {
    final doc = documentFromText('a\n${'b' * 4500}\nc', highlightJson: false);
    expect(doc.rows.length, 5);
    expect(doc.lineCount, 3);
    expect(doc.rows.lineCount, 3);
  });
}
