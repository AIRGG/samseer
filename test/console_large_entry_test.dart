import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:samseer/src/core/samseer_configuration.dart';
import 'package:samseer/src/core/samseer_core.dart';
import 'package:samseer/src/feature/floating_bubble.dart';
import 'package:samseer/src/model/console_log.dart';
import 'package:samseer/src/model/http_call.dart';
import 'package:samseer/src/model/http_request.dart';
import 'package:samseer/src/ui/screen/call_list_screen.dart';
import 'package:samseer/src/ui/screen/console_view.dart';
import 'package:samseer/src/ui/text/body_document.dart';
import 'package:samseer/src/ui/widget/body_text_sliver.dart';

// Top level so the closure sent to the isolate captures only the log.
BodyDocument Function() _consoleDoc(SamseerConsoleLog log) =>
    () => documentFromText(
      consoleEntryText(log),
      highlightJson: log.data != null && log.data!.isNotEmpty,
    );

void main() {
  final t = DateTime(2026, 11, 5, 14, 30);

  SamseerConsoleLog log(
    int id, {
    String message = 'hello',
    List<Object?>? data,
    String? stack,
    SamseerLogLevel level = SamseerLogLevel.log,
  }) => SamseerConsoleLog(
    id: id,
    level: level,
    source: SamseerLogSource.webView,
    message: message,
    time: t,
    data: data,
    stackTrace: stack,
  );

  group('consolePreview', () {
    test('short messages are unchanged', () {
      expect(consolePreview('abc'), 'abc');
      final exact = 'x' * kConsolePreviewChars;
      expect(consolePreview(exact), exact);
    });

    test('long messages are cut to the preview length plus an ellipsis', () {
      final preview = consolePreview('y' * 2000000);
      expect(preview.length, kConsolePreviewChars + 1);
      expect(preview.endsWith('…'), isTrue);
    });
  });

  group('consoleEntryText', () {
    test('message only', () {
      expect(consoleEntryText(log(1, message: 'plain')), 'plain');
    });

    test('message, pretty data items and stack trace', () {
      final text = consoleEntryText(
        log(
          1,
          message: 'boom {"a":1}',
          data: [
            {'a': 1},
            [true],
          ],
          stack: 'at f (app.js:1)',
        ),
      );
      expect(
        text,
        'boom {"a":1}\n\nDATA\n{\n  "a": 1\n}\n[\n  true\n]'
        '\n\nSTACK TRACE\nat f (app.js:1)',
      );
    });
  });

  testWidgets('large console entry renders lazily with Download .txt', (
    tester,
  ) async {
    final big = List.generate(20000, (i) => {'id': i, 'name': 'row $i'});
    final entry = log(1, message: jsonEncode(big), data: [big]);
    await tester.runAsync(
      () => loadBodyDocument(entry, 'console', _consoleDoc(entry)),
    );
    await tester.pumpWidget(MaterialApp(home: ConsoleDetailScreen(log: entry)));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();

    final rows = find.byType(BodyRowView).evaluate().length;
    expect(rows, greaterThan(0));
    expect(rows, lessThan(300));
    expect(find.textContaining('Download .txt'), findsOneWidget);
  });

  group('counts', () {
    late SamseerCore core;

    setUp(() {
      core = SamseerCore(
        configuration: const SamseerConfiguration(showInspectorOnShake: false),
      );
      for (var i = 0; i < 2; i++) {
        core.addCall(
          SamseerHttpCall(
            id: core.nextId(),
            method: 'GET',
            uri: 'https://example.com/a',
            endpoint: '/a',
            server: 'example.com',
            secure: true,
            client: 'Dio',
            createdAt: t,
            request: SamseerHttpRequest(time: t),
          ),
        );
      }
      for (var i = 0; i < 3; i++) {
        core.addConsoleLog(log(core.nextId()));
      }
    });

    tearDown(() => core.dispose());

    testWidgets('bubble shows calls plus console entries', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SamseerOverlay(core: core, child: const SizedBox.expand()),
        ),
      );
      expect(find.text('5'), findsOneWidget);
    });

    testWidgets('Network tab has a badge with the call count', (tester) async {
      await tester.pumpWidget(MaterialApp(home: CallListScreen(core: core)));
      await tester.pump();
      final nav = find.byType(NavigationBar);
      expect(
        find.descendant(of: nav, matching: find.text('2')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: nav, matching: find.text('3')),
        findsOneWidget,
      );
    });
  });
}
