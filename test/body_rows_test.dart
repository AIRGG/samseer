import 'package:flutter_test/flutter_test.dart';
import 'package:samseer/src/ui/text/body_rows.dart';

List<BodyToken> _significant(String line) => tokenizeJsonLine(line)
    .where(
      (t) => t.kind != BodyTokenKind.plain && t.kind != BodyTokenKind.punct,
    )
    .toList();

void main() {
  group('buildRows', () {
    test('numbers source lines from 1', () {
      final rows = buildRows('a\nb\nc', highlightJson: false);
      expect(rows.length, 3);
      expect(rows.map((r) => r.lineNumber), [1, 2, 3]);
      expect(rows.map((r) => r.text), ['a', 'b', 'c']);
    });

    test('strips CR from CRLF', () {
      final rows = buildRows('a\r\nb', highlightJson: false);
      expect(rows.map((r) => r.text), ['a', 'b']);
      expect(rows.any((r) => r.text.contains('\r')), isFalse);
    });

    test('empty text gives one empty row', () {
      final rows = buildRows('', highlightJson: false);
      expect(rows.length, 1);
      expect(rows.first.lineNumber, 1);
      expect(rows.first.text, '');
    });

    test('chunks long lines into continuation rows', () {
      final line = List.generate(5000, (i) => 'abcdefghij'[i % 10]).join();
      final rows = buildRows(line, highlightJson: false, chunkSize: 2000);
      expect(rows.length, 3);
      expect(rows.map((r) => r.lineNumber), [1, null, null]);
      expect(rows.every((r) => r.text.length <= 2000), isTrue);
      expect(rows.map((r) => r.text).join(), line);
    });

    test('500 KB single line stays bounded', () {
      final rows = buildRows('x' * 500000, highlightJson: false);
      expect(rows.every((r) => r.text.length <= 2000), isTrue);
      expect(rows.length, 250);
    });

    test('highlighted chunks keep token kinds', () {
      final line = '"k": "${'y' * 4500}"';
      final rows = buildRows(line, highlightJson: true);
      expect(rows.length, 3);
      expect(rows.map((r) => r.text).join(), line);
      for (final row in rows.skip(1)) {
        expect(row.lineNumber, isNull);
        expect(row.tokens.every((t) => t.kind == BodyTokenKind.string), isTrue);
      }
    });

    test('plain mode makes one plain token per row', () {
      final rows = buildRows('{"a":1}', highlightJson: false);
      expect(rows.single.tokens.length, 1);
      expect(rows.single.tokens.single.kind, BodyTokenKind.plain);
    });
  });

  group('tokenizeJsonLine', () {
    test('tokenizes key vs string value', () {
      const line = '  "id": "abc",';
      final tokens = tokenizeJsonLine(line);
      expect(tokens.map((t) => t.text).join(), line);
      final sig = _significant(line);
      expect(sig.length, 2);
      expect(sig[0].kind, BodyTokenKind.key);
      expect(sig[0].text, '"id"');
      expect(sig[1].kind, BodyTokenKind.string);
      expect(sig[1].text, '"abc"');
    });

    test('tokenizes number, bool, null, brackets', () {
      const line = '  "n": 1.5e3, "b": true, "z": null, "a": [{}]';
      final tokens = tokenizeJsonLine(line);
      expect(tokens.map((t) => t.text).join(), line);
      bool has(BodyTokenKind k, String t) =>
          tokens.any((x) => x.kind == k && x.text == t);
      expect(has(BodyTokenKind.number, '1.5e3'), isTrue);
      expect(has(BodyTokenKind.boolean, 'true'), isTrue);
      expect(has(BodyTokenKind.nullValue, 'null'), isTrue);
      expect(has(BodyTokenKind.bracket, '['), isTrue);
      expect(has(BodyTokenKind.bracket, '{'), isTrue);
      expect(has(BodyTokenKind.bracket, '}'), isTrue);
      expect(has(BodyTokenKind.bracket, ']'), isTrue);
    });

    test('escaped quotes stay inside the string', () {
      const line = '"k": "a\\"b"';
      final strings = tokenizeJsonLine(
        line,
      ).where((t) => t.kind == BodyTokenKind.string).toList();
      expect(strings.length, 1);
      expect(strings.single.text, '"a\\"b"');
    });
  });
}
