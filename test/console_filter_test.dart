import 'package:flutter_test/flutter_test.dart';
import 'package:samseer/samseer.dart';
import 'package:samseer/src/ui/screen/console_view.dart';

void main() {
  SamseerConsoleLog entry(
    int id, {
    SamseerLogLevel level = SamseerLogLevel.log,
    SamseerLogSource source = SamseerLogSource.app,
    String message = 'msg',
  }) {
    return SamseerConsoleLog(
      id: id,
      level: level,
      source: source,
      message: message,
      time: DateTime.now(),
    );
  }

  final logs = [
    entry(
      1,
      level: SamseerLogLevel.error,
      source: SamseerLogSource.webView,
      message: 'network exploded',
    ),
    entry(
      2,
      level: SamseerLogLevel.warn,
      source: SamseerLogSource.app,
      message: 'careful now',
    ),
    entry(
      3,
      level: SamseerLogLevel.log,
      source: SamseerLogSource.app,
      message: 'just info',
    ),
  ];

  test('no filters returns everything', () {
    expect(applyConsoleFilter(logs).length, 3);
  });

  test('level filter', () {
    final r = applyConsoleFilter(logs, level: SamseerLogLevel.error);
    expect(r.map((l) => l.id), [1]);
  });

  test('source filter', () {
    final r = applyConsoleFilter(logs, source: SamseerLogSource.webView);
    expect(r.map((l) => l.id), [1]);
  });

  test('query matches message case-insensitively', () {
    final r = applyConsoleFilter(logs, query: 'EXPLODED');
    expect(r.map((l) => l.id), [1]);
  });

  test('combined level + query', () {
    final r = applyConsoleFilter(
      logs,
      level: SamseerLogLevel.warn,
      query: 'careful',
    );
    expect(r.map((l) => l.id), [2]);
  });
}
