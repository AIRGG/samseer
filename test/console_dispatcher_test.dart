import 'package:flutter_test/flutter_test.dart';
import 'package:samseer/samseer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WebView console events', () {
    test('log event becomes a webView console entry', () {
      final samseer = Samseer(
        configuration: const SamseerConfiguration(showInspectorOnShake: false),
      );
      samseer.recordWebViewEvent({
        'kind': 'log',
        'level': 'warn',
        'message': 'hello {"a":1}',
        'data': [
          {'a': 1}
        ],
      });
      final logs = samseer.consoleLogs;
      expect(logs, hasLength(1));
      expect(logs.single.level, SamseerLogLevel.warn);
      expect(logs.single.source, SamseerLogSource.webView);
      expect(logs.single.message, 'hello {"a":1}');
      expect(logs.single.data, [
        {'a': 1}
      ]);
      samseer.dispose();
    });

    test('unknown level falls back to log', () {
      final samseer = Samseer(
        configuration: const SamseerConfiguration(showInspectorOnShake: false),
      );
      samseer.recordWebViewEvent(
          {'kind': 'log', 'level': 'trace', 'message': 'x'});
      expect(samseer.consoleLogs.single.level, SamseerLogLevel.log);
      samseer.dispose();
    });

    test('error event carries stack', () {
      final samseer = Samseer(
        configuration: const SamseerConfiguration(showInspectorOnShake: false),
      );
      samseer.recordWebViewEvent({
        'kind': 'log',
        'level': 'error',
        'message': 'boom',
        'stack': 'at foo (app.js:1)',
      });
      expect(samseer.consoleLogs.single.stackTrace, 'at foo (app.js:1)');
      samseer.dispose();
    });
  });

  group('network-error bridging', () {
    test('err event also creates an error console entry when enabled', () {
      final samseer = Samseer(
        configuration: const SamseerConfiguration(showInspectorOnShake: false),
      );
      samseer.recordWebViewEvent({
        'kind': 'req',
        'cid': 'c1',
        'method': 'GET',
        'url': 'https://api.example.com/x',
        'headers': {},
      });
      samseer.recordWebViewEvent(
          {'kind': 'err', 'cid': 'c1', 'message': 'Network error'});
      // Call recorded with error.
      expect(samseer.calls.single.hasError, true);
      // Console entry bridged.
      final consoleErrors = samseer.consoleLogs
          .where((l) => l.level == SamseerLogLevel.error)
          .toList();
      expect(consoleErrors, hasLength(1));
      expect(consoleErrors.single.source, SamseerLogSource.webView);
      expect(consoleErrors.single.message, contains('api.example.com'));
      samseer.dispose();
    });

    test('bridging disabled suppresses the console entry', () {
      final samseer = Samseer(
        configuration: const SamseerConfiguration(
          showInspectorOnShake: false,
          captureNetworkErrorsInConsole: false,
        ),
      );
      samseer.recordWebViewEvent({
        'kind': 'req',
        'cid': 'c1',
        'method': 'GET',
        'url': 'https://api.example.com/x',
        'headers': {},
      });
      samseer.recordWebViewEvent(
          {'kind': 'err', 'cid': 'c1', 'message': 'Network error'});
      expect(samseer.consoleLogs, isEmpty);
      samseer.dispose();
    });
  });
}
