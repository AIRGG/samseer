import 'package:flutter_test/flutter_test.dart';
import 'package:samseer/src/ui/text/body_rows.dart';

List<BodyToken> _significant(String line) => tokenizeJsonLine(line)
    .where(
      (t) => t.kind != BodyTokenKind.plain && t.kind != BodyTokenKind.punct,
    )
    .toList();

// The eager row builder this feature shipped first: tokenize the whole line,
// then slice the tokens at chunk boundaries. Lazy rows must match it exactly.
List<List<BodyToken>> _eagerRows(String line, int chunkSize) {
  if (line.length <= chunkSize) {
    return [
      line.isEmpty
          ? [BodyToken(BodyTokenKind.plain, line)]
          : tokenizeJsonLine(line),
    ];
  }
  final out = <List<BodyToken>>[];
  var current = <BodyToken>[];
  var used = 0;
  void emit() {
    out.add(current);
    current = <BodyToken>[];
    used = 0;
  }

  for (final token in tokenizeJsonLine(line)) {
    var rest = token.text;
    while (rest.isNotEmpty) {
      final room = chunkSize - used;
      if (rest.length <= room) {
        current.add(BodyToken(token.kind, rest));
        used += rest.length;
        rest = '';
      } else {
        current.add(BodyToken(token.kind, rest.substring(0, room)));
        rest = rest.substring(room);
        emit();
      }
    }
    if (used == chunkSize) emit();
  }
  if (current.isNotEmpty) emit();
  return out;
}

String _dump(List<BodyToken> tokens) =>
    tokens.map((t) => '${t.kind.name}:${t.text}').join('|');

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

    test('lazy highlighted chunks match the eager slicer', () {
      const lines = [
        '{"key": "value", "n": -12.5e+3, "t": true, "f": false, "z": null}',
        '  "a b c" :  [1,2,3], "esc\\"aped": "x\\"y", "k":"v"',
        '[{"id":1,"name":"item number 1","active":true,"score":1.5}]',
        '"unterminated string that runs to the end',
        'plain words then "s" and -x and 1.e5 and tru fals nul',
      ];
      for (final line in lines) {
        for (var size = 1; size <= 17; size++) {
          final rows = buildRows(line, highlightJson: true, chunkSize: size);
          final expected = _eagerRows(line, size);
          expect(rows.length, expected.length, reason: '$line @ $size');
          for (var i = 0; i < rows.length; i++) {
            expect(
              _dump(rows[i].tokens),
              _dump(expected[i]),
              reason: 'row $i of $line @ $size',
            );
          }
        }
      }
    });

    test('lazy rows work across many lines and CRLF', () {
      final text = '{\r\n  "a": "${'q' * 9}",\r\n  "bb": 12345678\r\n}';
      final rows = buildRows(text, highlightJson: true, chunkSize: 5);
      final lines = text
          .split('\n')
          .map((l) => l.endsWith('\r') ? l.substring(0, l.length - 1) : l);
      final expected = [for (final l in lines) ..._eagerRows(l, 5)];
      expect(rows.map((r) => _dump(r.tokens)), expected.map(_dump));
    });

    test('rows are offsets into the text, tokens built on demand', () {
      final text = '{"a": "${'y' * 4500}"}\n[1]';
      final rows = buildRows(text, highlightJson: true);
      expect(rows, isA<BodyRows>());
      expect(identical(rows.text, text), isTrue);
      expect(rows.lineCount, 2);
      expect(identical(rows[0].tokens, rows[0].tokens), isFalse);
      expect(rows.map((r) => r.lineNumber), [1, null, null, 2]);
      expect(rows.map((r) => r.text).join(), text.replaceAll('\n', ''));
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
