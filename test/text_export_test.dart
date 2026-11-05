import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:samseer/src/core/samseer_configuration.dart';
import 'package:samseer/src/feature/text_export.dart';
import 'package:samseer/src/ui/text/body_document.dart';
import 'package:samseer/src/ui/theme/samseer_theme.dart';
import 'package:samseer/src/ui/widget/export_text_button.dart';

BodyDocument _doc(String text) => documentFromText(text, highlightJson: false);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final originalSaver = SamseerTextExport.saver;
  late List<String> clipboard;
  late List<String> saved;

  setUp(() {
    clipboard = [];
    saved = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard.add((call.arguments as Map)['text'] as String);
          }
          return null;
        });
  });

  tearDown(() {
    SamseerTextExport.saver = originalSaver;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Future<void> pump(
    WidgetTester tester,
    BodyDocument? doc, {
    int limitBytes = kCopyLimitBytes,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        theme: SamseerTheme.theme(),
        home: Scaffold(
          body: ExportTextButton(
            copyLabel: 'Copy body',
            document: doc,
            fileName: 'out.txt',
            copiedTitle: 'Body copied',
            limitBytes: limitBytes,
          ),
        ),
      ),
    );
  }

  test('limit boundary', () {
    expect(exceedsCopyLimit(102400), isFalse);
    expect(exceedsCopyLimit(102401), isTrue);
  });

  test('custom limit', () {
    expect(exceedsCopyLimit(512, limitBytes: 512), isFalse);
    expect(exceedsCopyLimit(513, limitBytes: 512), isTrue);
    expect(exceedsCopyLimit(1, limitBytes: 0), isTrue);
  });

  test('configuration copyLimitBytes defaults to 100 KB and copies over', () {
    const config = SamseerConfiguration();
    expect(config.copyLimitBytes, kCopyLimitBytes);
    expect(config.copyLimitBytes, 102400);
    final custom = config.copyWith(copyLimitBytes: 512 * 1024);
    expect(custom.copyLimitBytes, 524288);
    expect(custom.copyWith(maxCallsCount: 10).copyLimitBytes, 524288);
  });

  testWidgets('button follows a custom limit', (tester) async {
    await pump(tester, _doc('0123456789'), limitBytes: 5);
    expect(find.textContaining('Download .txt'), findsOneWidget);

    await pump(tester, _doc('x' * 200000), limitBytes: 512 * 1024);
    expect(find.text('Copy body'), findsOneWidget);
    expect(find.textContaining('Download .txt'), findsNothing);
  });

  test('file name', () {
    final t = DateTime(2026, 11, 5, 13, 41, 6);
    expect(
      buildExportFileName(
        part: 'response',
        method: 'GET',
        endpoint: '/api/v1/Orders?x=1',
        time: t,
      ),
      'samseer-get-api-v1-orders-x-1-response-20261105-134106.txt',
    );
    expect(
      buildExportFileName(part: 'calls', time: t),
      'samseer-calls-20261105-134106.txt',
    );
  });

  testWidgets('small body copies', (tester) async {
    SamseerTextExport.saver = (n, b) async {
      saved.add(n);
      return true;
    };
    await pump(tester, _doc('0123456789'));
    expect(find.text('Copy body'), findsOneWidget);
    await tester.tap(find.text('Copy body'));
    await tester.pump();
    expect(clipboard, ['0123456789']);
    expect(saved, isEmpty);
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('large body downloads', (tester) async {
    final text = 'a' * 102401;
    Uint8List? gotBytes;
    SamseerTextExport.saver = (n, b) async {
      saved.add(n);
      gotBytes = b;
      return true;
    };
    await pump(tester, _doc(text));
    expect(find.textContaining('Download .txt'), findsOneWidget);
    await tester.tap(find.textContaining('Download .txt'));
    await tester.pump();
    await tester.pump();
    expect(saved, ['out.txt']);
    expect(gotBytes, utf8.encode(text));
    expect(clipboard, isEmpty);
    expect(find.text('Saved out.txt'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('cancel does nothing', (tester) async {
    SamseerTextExport.saver = (n, b) async {
      saved.add(n);
      return false;
    };
    await pump(tester, _doc('a' * 102401));
    await tester.tap(find.textContaining('Download .txt'));
    await tester.pump();
    await tester.pump();
    expect(saved, ['out.txt']);
    expect(find.textContaining('Saved'), findsNothing);
    expect(clipboard, isEmpty);
  });

  testWidgets('save error shows error toast', (tester) async {
    SamseerTextExport.saver = (n, b) async => throw Exception('disk full');
    await pump(tester, _doc('a' * 102401));
    await tester.tap(find.textContaining('Download .txt'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Could not save file'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('loading document disables the button', (tester) async {
    await pump(tester, null);
    final button = tester.widget<ButtonStyleButton>(
      find.bySubtype<ButtonStyleButton>(),
    );
    expect(button.onPressed, isNull);
    expect(find.text('Copy body'), findsOneWidget);
  });
}
