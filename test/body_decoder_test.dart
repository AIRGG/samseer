import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:samseer/samseer.dart';
import 'package:samseer/src/feature/exporter.dart';
import 'package:samseer/src/interceptor/body_decoder.dart';

void main() {
  group('classifyContentType', () {
    test('classifies every content type samseer promises to handle', () {
      expect(classifyContentType('application/json'),
          SamseerBodyKind.json);
      expect(classifyContentType('application/json; charset=utf-8'),
          SamseerBodyKind.json);
      expect(classifyContentType('multipart/form-data; boundary=x'),
          SamseerBodyKind.multipart);
      expect(classifyContentType('application/x-www-form-urlencoded'),
          SamseerBodyKind.formUrlEncoded);
      expect(classifyContentType('text/plain'), SamseerBodyKind.text);
      expect(classifyContentType('text/html'), SamseerBodyKind.html);
      expect(classifyContentType('application/xml'), SamseerBodyKind.xml);
      expect(classifyContentType('text/xml'), SamseerBodyKind.xml);
      expect(classifyContentType('application/octet-stream'),
          SamseerBodyKind.binary);
      expect(classifyContentType('application/pdf'), SamseerBodyKind.pdf);
      expect(classifyContentType('text/csv'), SamseerBodyKind.csv);
      expect(classifyContentType('image/jpeg'), SamseerBodyKind.image);
      expect(classifyContentType('image/png'), SamseerBodyKind.image);
    });

    test('isBinaryBodyKind is true only for image/pdf/octet-stream', () {
      expect(isBinaryBodyKind(SamseerBodyKind.image), isTrue);
      expect(isBinaryBodyKind(SamseerBodyKind.pdf), isTrue);
      expect(isBinaryBodyKind(SamseerBodyKind.binary), isTrue);
      expect(isBinaryBodyKind(SamseerBodyKind.json), isFalse);
      expect(isBinaryBodyKind(SamseerBodyKind.text), isFalse);
    });
  });

  group('samseerDecodeBody', () {
    test('application/json parses into Map/List', () {
      final decoded =
          samseerDecodeBody(utf8.encode('{"a":1}'), 'application/json');
      expect(decoded, {'a': 1});
    });

    test('malformed application/json falls back to raw text', () {
      final decoded =
          samseerDecodeBody(utf8.encode('not json'), 'application/json');
      expect(decoded, 'not json');
    });

    test('application/x-www-form-urlencoded parses into a field map', () {
      final decoded = samseerDecodeBody(
        utf8.encode('a=1&b=hello+world'),
        'application/x-www-form-urlencoded',
      );
      expect(decoded, {'a': '1', 'b': 'hello world'});
    });

    test('text/plain, text/html, application/xml, text/csv stay as text', () {
      for (final ct in [
        'text/plain',
        'text/html',
        'application/xml',
        'text/csv',
      ]) {
        final decoded = samseerDecodeBody(utf8.encode('hello'), ct);
        expect(decoded, isA<String>(), reason: ct);
        expect(decoded, 'hello', reason: ct);
      }
    });

    test('image/png captures bytes as SamseerBinaryBody', () {
      final bytes = List<int>.generate(16, (i) => i);
      final decoded = samseerDecodeBody(bytes, 'image/png');
      expect(decoded, isA<SamseerBinaryBody>());
      final binary = decoded as SamseerBinaryBody;
      expect(binary.contentType, 'image/png');
      expect(binary.totalSize, 16);
      expect(binary.bytes, bytes);
      expect(binary.truncated, isFalse);
    });

    test('application/pdf and application/octet-stream are binary too', () {
      final bytes = [0x25, 0x50, 0x44, 0x46];
      for (final ct in ['application/pdf', 'application/octet-stream']) {
        final decoded = samseerDecodeBody(bytes, ct);
        expect(decoded, isA<SamseerBinaryBody>(), reason: ct);
      }
    });

    test('binary bodies beyond the capture cap keep size but drop bytes', () {
      final huge = List<int>.filled(kSamseerMaxBinaryCapture + 1, 0);
      final decoded = samseerDecodeBody(huge, 'application/octet-stream');
      final binary = decoded as SamseerBinaryBody;
      expect(binary.totalSize, huge.length);
      expect(binary.bytes, isNull);
      expect(binary.truncated, isTrue);
    });

    test('invalid UTF-8 is treated as binary regardless of content type', () {
      final invalidUtf8 = [0xFF, 0xFE, 0x00, 0x01];
      final decoded = samseerDecodeBody(invalidUtf8, 'text/plain');
      expect(decoded, isA<SamseerBinaryBody>());
    });
  });

  group('Exporter content-type awareness', () {
    test('buildCurl encodes form-urlencoded Map as key=value pairs', () {
      final call = _callWithRequestBody(
        body: {'a': '1', 'b': 'two'},
        contentType: 'application/x-www-form-urlencoded',
      );
      final curl = Exporter.buildCurl(call);
      expect(curl, contains("-d 'a=1&b=two'"));
    });

    test('buildCurl represents multipart bodies with -F flags', () {
      final call = _callWithRequestBody(
        body: const SamseerMultipartBody(
          fields: {'name': 'sam'},
          files: [
            SamseerMultipartFilePart(
              field: 'avatar',
              filename: 'photo.jpg',
              contentType: 'image/jpeg',
              length: 1024,
            ),
          ],
        ),
        contentType: 'multipart/form-data; boundary=x',
      );
      final curl = Exporter.buildCurl(call);
      expect(curl, contains("-F 'name=sam'"));
      expect(curl, contains("-F 'avatar=@photo.jpg;type=image/jpeg'"));
    });

    test('buildCurl omits binary bodies with a descriptive comment', () {
      final call = _callWithRequestBody(
        body: const SamseerBinaryBody(totalSize: 2048, contentType: 'image/png'),
        contentType: 'image/png',
      );
      final curl = Exporter.buildCurl(call);
      expect(curl, contains('# binary body omitted (image/png, 2.0 KB)'));
      expect(curl, isNot(contains(' -d ')));
    });
  });
}

SamseerHttpCall _callWithRequestBody({
  required dynamic body,
  required String contentType,
}) {
  return SamseerHttpCall(
    id: 1,
    method: 'POST',
    uri: 'https://example.com/api',
    endpoint: '/api',
    server: 'example.com',
    secure: true,
    client: 'test',
    createdAt: DateTime.now(),
    request: SamseerHttpRequest(
      time: DateTime.now(),
      body: body,
      contentType: contentType,
    ),
  );
}
