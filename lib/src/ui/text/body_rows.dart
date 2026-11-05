/// Pure Dart row model and JSON line tokenizer for virtualized bodies.
/// No Flutter imports: this runs inside `compute`.
library;

import 'dart:collection';
import 'dart:typed_data';

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

/// Max characters per row; longer lines wrap into continuation rows.
const int kRowChunkSize = 2000;

bool _isDigit(int c) => c >= 0x30 && c <= 0x39;

/// Tokenizes a single line of (pretty printed) JSON in one left-to-right scan.
List<BodyToken> tokenizeJsonLine(String line) {
  final tokens = <BodyToken>[];
  _scanJson(
    line,
    0,
    line.length,
    line.length,
    (kind, s, e) => tokens.add(BodyToken(kind, line.substring(s, e))),
  );
  return tokens;
}

typedef _Emit = void Function(BodyTokenKind kind, int start, int end);

const int _quote = 0x22;
const int _backslash = 0x5C;
const int _space = 0x20;
const int _tab = 0x09;
const int _colon = 0x3A;
const int _comma = 0x2C;
const int _minus = 0x2D;
const int _dot = 0x2E;
const int _plus = 0x2B;

bool _isBracket(int c) => c == 0x7B || c == 0x7D || c == 0x5B || c == 0x5D;

/// Scans JSON tokens of `s` in `[from, to)` and reports them as offsets.
/// [limit] bounds only the key lookahead (whitespace then `:` after a
/// string), which may look past [to].
void _scanJson(String s, int from, int to, int limit, _Emit emit) {
  var i = from;
  var plainStart = -1;

  void flushPlain(int end) {
    if (plainStart >= 0) {
      emit(BodyTokenKind.plain, plainStart, end);
      plainStart = -1;
    }
  }

  bool literal(String word, int at) =>
      at + word.length <= to && s.startsWith(word, at);

  while (i < to) {
    final c = s.codeUnitAt(i);

    if (c == _quote) {
      flushPlain(i);
      var j = i + 1;
      var closed = false;
      while (j < to) {
        final d = s.codeUnitAt(j);
        if (d == _backslash) {
          j += 2;
          continue;
        }
        if (d == _quote) {
          j++;
          closed = true;
          break;
        }
        j++;
      }
      if (j > to) j = to;
      var kind = BodyTokenKind.string;
      if (closed) {
        var k = j;
        while (k < limit &&
            (s.codeUnitAt(k) == _space || s.codeUnitAt(k) == _tab)) {
          k++;
        }
        if (k < limit && s.codeUnitAt(k) == _colon) kind = BodyTokenKind.key;
      }
      emit(kind, i, j);
      i = j;
    } else if (_isDigit(c) ||
        (c == _minus && i + 1 < to && _isDigit(s.codeUnitAt(i + 1)))) {
      flushPlain(i);
      var j = i + 1;
      while (j < to && _isDigit(s.codeUnitAt(j))) {
        j++;
      }
      if (j + 1 < to &&
          s.codeUnitAt(j) == _dot &&
          _isDigit(s.codeUnitAt(j + 1))) {
        j++;
        while (j < to && _isDigit(s.codeUnitAt(j))) {
          j++;
        }
      }
      if (j < to && (s.codeUnitAt(j) | 0x20) == 0x65) {
        var k = j + 1;
        if (k < to && (s.codeUnitAt(k) == _plus || s.codeUnitAt(k) == _minus)) {
          k++;
        }
        if (k < to && _isDigit(s.codeUnitAt(k))) {
          while (k < to && _isDigit(s.codeUnitAt(k))) {
            k++;
          }
          j = k;
        }
      }
      emit(BodyTokenKind.number, i, j);
      i = j;
    } else if (literal('true', i)) {
      flushPlain(i);
      emit(BodyTokenKind.boolean, i, i + 4);
      i += 4;
    } else if (literal('false', i)) {
      flushPlain(i);
      emit(BodyTokenKind.boolean, i, i + 5);
      i += 5;
    } else if (literal('null', i)) {
      flushPlain(i);
      emit(BodyTokenKind.nullValue, i, i + 4);
      i += 4;
    } else if (_isBracket(c)) {
      flushPlain(i);
      emit(BodyTokenKind.bracket, i, i + 1);
      i++;
    } else if (c == _comma || c == _colon) {
      flushPlain(i);
      emit(BodyTokenKind.punct, i, i + 1);
      i++;
    } else {
      if (plainStart < 0) plainStart = i;
      i++;
    }
  }
  flushPlain(to);
}

/// Marks "no token crosses this row edge" in the head and tail kind lists.
const int _noKind = 255;

/// One row of a [BodyRows]: a view, its tokens are built on each access.
class BodyRow {
  const BodyRow._(this._rows, this._index);

  final BodyRows _rows;
  final int _index;

  /// Source line number (1-based). Null marks a continuation row.
  int? get lineNumber {
    final n = _rows._lines[_index];
    return n == 0 ? null : n;
  }

  String get text =>
      _rows.text.substring(_rows._starts[_index], _rows._ends[_index]);

  /// Tokens of this row, computed now from the row's slice of the text.
  List<BodyToken> get tokens => _rows._tokensOf(_index);
}

/// Rows of a body stored as offsets into [text], about 22 bytes per row on
/// top of the text itself. A JSON token cut by a row edge has its kind kept
/// on both sides (head of the next row, tail of this one) so a row can be
/// tokenized alone and still match the whole line's coloring.
class BodyRows extends ListBase<BodyRow> {
  BodyRows._(
    this.text, {
    required this.highlightJson,
    required this.lineCount,
    required Int32List starts,
    required Int32List ends,
    required Int32List lines,
    required Int32List headEnds,
    required Uint8List headKinds,
    required Int32List tailStarts,
    required Uint8List tailKinds,
  }) : _starts = starts,
       _ends = ends,
       _lines = lines,
       _headEnds = headEnds,
       _headKinds = headKinds,
       _tailStarts = tailStarts,
       _tailKinds = tailKinds;

  final String text;
  final bool highlightJson;

  /// Number of source lines (continuation rows are not counted).
  final int lineCount;

  final Int32List _starts;
  final Int32List _ends;

  /// 1-based line number, 0 for a continuation row.
  final Int32List _lines;
  final Int32List _headEnds;
  final Uint8List _headKinds;
  final Int32List _tailStarts;
  final Uint8List _tailKinds;

  @override
  int get length => _starts.length;

  @override
  set length(int value) => throw UnsupportedError('BodyRows is read only');

  @override
  BodyRow operator [](int index) {
    RangeError.checkValidIndex(index, this);
    return BodyRow._(this, index);
  }

  @override
  void operator []=(int index, BodyRow value) =>
      throw UnsupportedError('BodyRows is read only');

  List<BodyToken> _tokensOf(int r) {
    final start = _starts[r];
    final end = _ends[r];
    if (!highlightJson || start == end) {
      return [BodyToken(BodyTokenKind.plain, text.substring(start, end))];
    }
    final tokens = <BodyToken>[];
    var pos = start;
    final head = _headKinds[r];
    if (head != _noKind) {
      pos = _headEnds[r];
      tokens.add(
        BodyToken(BodyTokenKind.values[head], text.substring(start, pos)),
      );
    }
    final tailStart = _tailStarts[r];
    if (pos < tailStart) {
      _scanJson(
        text,
        pos,
        tailStart,
        text.length,
        (kind, s, e) => tokens.add(BodyToken(kind, text.substring(s, e))),
      );
    }
    if (tailStart < end) {
      tokens.add(
        BodyToken(
          BodyTokenKind.values[_tailKinds[r]],
          text.substring(tailStart, end),
        ),
      );
    }
    return tokens;
  }
}

/// Splits [text] into numbered rows. Lines longer than [chunkSize] become
/// continuation rows (null line number). With [highlightJson], each row's
/// tokens carry JSON kinds; otherwise each row has one plain token.
BodyRows buildRows(
  String text, {
  required bool highlightJson,
  int chunkSize = kRowChunkSize,
}) {
  final starts = <int>[];
  final ends = <int>[];
  final lines = <int>[];
  final headEnds = <int>[];
  final headKinds = <int>[];
  final tailStarts = <int>[];
  final tailKinds = <int>[];

  void addRow(int start, int end, int line) {
    starts.add(start);
    ends.add(end);
    lines.add(line);
    headEnds.add(start);
    headKinds.add(_noKind);
    tailStarts.add(end);
    tailKinds.add(_noKind);
  }

  var lineStart = 0;
  var number = 0;
  while (true) {
    number++;
    final nl = text.indexOf('\n', lineStart);
    final next = nl < 0 ? text.length : nl;
    var lineEnd = next;
    if (lineEnd > lineStart && text.codeUnitAt(lineEnd - 1) == 0x0D) {
      lineEnd--;
    }

    if (lineEnd - lineStart <= chunkSize) {
      addRow(lineStart, lineEnd, number);
    } else {
      final firstRow = starts.length;
      for (var s = lineStart; s < lineEnd; s += chunkSize) {
        final e = s + chunkSize < lineEnd ? s + chunkSize : lineEnd;
        addRow(s, e, s == lineStart ? number : 0);
      }
      if (highlightJson) {
        // Record every token that crosses a row edge.
        _scanJson(text, lineStart, lineEnd, text.length, (kind, s, e) {
          final a = (s - lineStart) ~/ chunkSize;
          final b = (e - 1 - lineStart) ~/ chunkSize;
          if (a == b) return;
          tailStarts[firstRow + a] = s;
          tailKinds[firstRow + a] = kind.index;
          for (var r = firstRow + a + 1; r <= firstRow + b; r++) {
            headKinds[r] = kind.index;
            headEnds[r] = e < ends[r] ? e : ends[r];
          }
        });
      }
    }

    if (nl < 0) break;
    lineStart = nl + 1;
  }

  return BodyRows._(
    text,
    highlightJson: highlightJson,
    lineCount: number,
    starts: Int32List.fromList(starts),
    ends: Int32List.fromList(ends),
    lines: Int32List.fromList(lines),
    headEnds: Int32List.fromList(headEnds),
    headKinds: Uint8List.fromList(headKinds),
    tailStarts: Int32List.fromList(tailStarts),
    tailKinds: Uint8List.fromList(tailKinds),
  );
}
