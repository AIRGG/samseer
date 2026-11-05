/// Pure Dart row model and JSON line tokenizer for virtualized bodies.
/// No Flutter imports: this runs inside `compute`.
library;

enum BodyTokenKind {
  plain,
  key,
  string,
  number,
  boolean,
  nullValue,
  bracket,
  punct,
}

class BodyToken {
  const BodyToken(this.kind, this.text);

  final BodyTokenKind kind;
  final String text;
}

class BodyRow {
  const BodyRow({this.lineNumber, required this.tokens});

  /// Source line number (1-based). Null marks a continuation row.
  final int? lineNumber;
  final List<BodyToken> tokens;

  String get text => tokens.map((t) => t.text).join();
}

/// Max characters per row; longer lines wrap into continuation rows.
const int kRowChunkSize = 2000;

bool _isDigit(int c) => c >= 0x30 && c <= 0x39;

/// Tokenizes a single line of (pretty printed) JSON in one left-to-right scan.
List<BodyToken> tokenizeJsonLine(String line) {
  final tokens = <BodyToken>[];
  final n = line.length;
  var i = 0;
  var plainStart = -1;

  void flushPlain(int end) {
    if (plainStart >= 0) {
      tokens
          .add(BodyToken(BodyTokenKind.plain, line.substring(plainStart, end)));
      plainStart = -1;
    }
  }

  while (i < n) {
    final c = line.codeUnitAt(i);
    final ch = line[i];

    if (ch == '"') {
      flushPlain(i);
      var j = i + 1;
      var closed = false;
      while (j < n) {
        final d = line[j];
        if (d == r'\') {
          j += 2;
          continue;
        }
        if (d == '"') {
          j++;
          closed = true;
          break;
        }
        j++;
      }
      if (j > n) j = n;
      var kind = BodyTokenKind.string;
      if (closed) {
        var k = j;
        while (k < n && (line[k] == ' ' || line[k] == '\t')) {
          k++;
        }
        if (k < n && line[k] == ':') kind = BodyTokenKind.key;
      }
      tokens.add(BodyToken(kind, line.substring(i, j)));
      i = j;
    } else if (_isDigit(c) ||
        (ch == '-' && i + 1 < n && _isDigit(line.codeUnitAt(i + 1)))) {
      flushPlain(i);
      var j = i + 1;
      while (j < n && _isDigit(line.codeUnitAt(j))) {
        j++;
      }
      if (j + 1 < n && line[j] == '.' && _isDigit(line.codeUnitAt(j + 1))) {
        j++;
        while (j < n && _isDigit(line.codeUnitAt(j))) {
          j++;
        }
      }
      if (j < n && (line[j] == 'e' || line[j] == 'E')) {
        var k = j + 1;
        if (k < n && (line[k] == '+' || line[k] == '-')) k++;
        if (k < n && _isDigit(line.codeUnitAt(k))) {
          while (k < n && _isDigit(line.codeUnitAt(k))) {
            k++;
          }
          j = k;
        }
      }
      tokens.add(BodyToken(BodyTokenKind.number, line.substring(i, j)));
      i = j;
    } else if (line.startsWith('true', i)) {
      flushPlain(i);
      tokens.add(const BodyToken(BodyTokenKind.boolean, 'true'));
      i += 4;
    } else if (line.startsWith('false', i)) {
      flushPlain(i);
      tokens.add(const BodyToken(BodyTokenKind.boolean, 'false'));
      i += 5;
    } else if (line.startsWith('null', i)) {
      flushPlain(i);
      tokens.add(const BodyToken(BodyTokenKind.nullValue, 'null'));
      i += 4;
    } else if (ch == '{' || ch == '}' || ch == '[' || ch == ']') {
      flushPlain(i);
      tokens.add(BodyToken(BodyTokenKind.bracket, ch));
      i++;
    } else if (ch == ',' || ch == ':') {
      flushPlain(i);
      tokens.add(BodyToken(BodyTokenKind.punct, ch));
      i++;
    } else {
      if (plainStart < 0) plainStart = i;
      i++;
    }
  }
  flushPlain(n);
  return tokens;
}

/// Splits [text] into numbered rows. Lines longer than [chunkSize] become
/// continuation rows (null line number). With [highlightJson], each row's
/// tokens carry JSON kinds; otherwise each row has one plain token.
List<BodyRow> buildRows(
  String text, {
  required bool highlightJson,
  int chunkSize = kRowChunkSize,
}) {
  final rows = <BodyRow>[];
  final lines = text.split('\n');
  for (var li = 0; li < lines.length; li++) {
    var line = lines[li];
    if (line.endsWith('\r')) line = line.substring(0, line.length - 1);
    final number = li + 1;

    if (line.length <= chunkSize) {
      final tokens = highlightJson && line.isNotEmpty
          ? tokenizeJsonLine(line)
          : [BodyToken(BodyTokenKind.plain, line)];
      rows.add(BodyRow(lineNumber: number, tokens: tokens));
      continue;
    }

    if (!highlightJson) {
      for (var s = 0; s < line.length; s += chunkSize) {
        final e = s + chunkSize < line.length ? s + chunkSize : line.length;
        rows.add(
          BodyRow(
            lineNumber: s == 0 ? number : null,
            tokens: [BodyToken(BodyTokenKind.plain, line.substring(s, e))],
          ),
        );
      }
      continue;
    }

    // Slice the full token list at chunk boundaries, splitting straddlers.
    var current = <BodyToken>[];
    var used = 0;
    var first = true;
    void emit() {
      rows.add(BodyRow(lineNumber: first ? number : null, tokens: current));
      first = false;
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
  }
  return rows;
}
