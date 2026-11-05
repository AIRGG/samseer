import 'package:flutter_test/flutter_test.dart';
import 'package:samseer/samseer.dart';

void main() {
  group('webViewInterceptorScript console hooks', () {
    test('patches all console levels', () {
      for (final level in ['log', 'info', 'warn', 'error', 'debug']) {
        expect(
          webViewInterceptorScript.contains("'$level'"),
          isTrue,
          reason: 'script should reference console level $level',
        );
      }
    });

    test('emits log events through the bridge', () {
      expect(webViewInterceptorScript.contains("kind: 'log'"), isTrue);
    });

    test('listens for uncaught errors and rejections', () {
      expect(webViewInterceptorScript.contains("addEventListener('error'"),
          isTrue);
      expect(webViewInterceptorScript.contains("'unhandledrejection'"), isTrue);
    });

    test('includes a circular-safe serializer (no [object Object])', () {
      expect(webViewInterceptorScript.contains('safeStringify'), isTrue);
      expect(webViewInterceptorScript.contains('[Circular]'), isTrue);
    });

    test('swallows rejected bridge calls to avoid a rejection loop', () {
      expect(
          webViewInterceptorScript.contains('p.catch(function () {})'), isTrue);
    });

    test('renders Error objects as name: message instead of {}', () {
      expect(
          webViewInterceptorScript.contains('value instanceof Error'), isTrue);
      expect(webViewInterceptorScript.contains('var msg = describe(reason);'),
          isTrue);
    });
  });
}
