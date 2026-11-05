import 'package:flutter_test/flutter_test.dart';
import 'package:samseer/samseer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SamseerConfiguration', () {
    test('defaults are sane', () {
      const config = SamseerConfiguration();
      expect(config.maxCallsCount, 1000);
      expect(config.showInspectorOnShake, true);
      expect(config.showFloatingBubble, false);
    });

    test('copyWith preserves untouched fields', () {
      const config = SamseerConfiguration(maxCallsCount: 50);
      final next = config.copyWith(showFloatingBubble: true);
      expect(next.maxCallsCount, 50);
      expect(next.showFloatingBubble, true);
      expect(next.showInspectorOnShake, true);
    });
  });

  group('SamseerHttpCall.state', () {
    SamseerHttpCall buildCall({int? status, SamseerHttpError? error}) {
      return SamseerHttpCall(
        id: 1,
        method: 'GET',
        uri: 'https://example.com/api',
        endpoint: '/api',
        server: 'example.com',
        secure: true,
        client: 'Dio',
        createdAt: DateTime.now(),
        request: SamseerHttpRequest(time: DateTime.now()),
        response: status != null
            ? SamseerHttpResponse(status: status, time: DateTime.now())
            : null,
        error: error,
      );
    }

    test('classifies status codes', () {
      expect(buildCall(status: 200).state, SamseerCallState.success);
      expect(buildCall(status: 301).state, SamseerCallState.redirect);
      expect(buildCall(status: 404).state, SamseerCallState.clientError);
      expect(buildCall(status: 500).state, SamseerCallState.serverError);
    });

    test('returns loading when no response or error', () {
      expect(buildCall().state, SamseerCallState.loading);
    });

    test('returns error when error is set', () {
      expect(
        buildCall(error: const SamseerHttpError(message: 'oops')).state,
        SamseerCallState.error,
      );
    });
  });

  group('Samseer', () {
    test('records calls and exposes them via stream', () async {
      final samseer = Samseer(
        configuration: const SamseerConfiguration(showInspectorOnShake: false),
      );
      addTearDown(samseer.dispose);

      expect(samseer.calls, isEmpty);

      final emitted = <int>[];
      final sub = samseer.callsStream.listen((c) => emitted.add(c.length));
      addTearDown(sub.cancel);

      samseer.clear();
      await Future<void>.delayed(Duration.zero);
      expect(emitted, contains(0));
    });

    test('recordRequest / recordResponse round-trip', () {
      final samseer = Samseer(
        configuration: const SamseerConfiguration(showInspectorOnShake: false),
      );
      addTearDown(samseer.dispose);

      final id = samseer.recordRequest(
        method: 'post',
        uri: 'https://api.example.com/v1/users?source=test',
        client: 'Custom',
        headers: {'content-type': 'application/json'},
        body: '{"a":1}',
      );

      expect(samseer.calls, hasLength(1));
      final call = samseer.calls.first;
      expect(call.id, id);
      expect(call.method, 'POST');
      expect(call.client, 'Custom');
      expect(call.endpoint, '/v1/users');
      expect(call.server, 'api.example.com');
      expect(call.secure, isTrue);
      expect(call.request.queryParameters, {'source': 'test'});
      expect(call.request.contentType, 'application/json');
      expect(call.loading, isTrue);

      samseer.recordResponse(id, status: 201, body: '{"id":42}');
      final updated = samseer.calls.first;
      expect(updated.response?.status, 201);
      expect(updated.loading, isFalse);
      expect(updated.state, SamseerCallState.success);
    });

    test('recordWebViewEvent dispatches req/res into a single call', () {
      final samseer = Samseer(
        configuration: const SamseerConfiguration(showInspectorOnShake: false),
      );
      addTearDown(samseer.dispose);

      samseer.recordWebViewEvent({
        'kind': 'req',
        'cid': 'cid-1',
        'method': 'GET',
        'url': 'https://api.example.com/items?page=2',
        'headers': {'accept': 'application/json'},
        'body': null,
      });

      expect(samseer.calls, hasLength(1));
      var call = samseer.calls.first;
      expect(call.client, 'WebView');
      expect(call.method, 'GET');
      expect(call.endpoint, '/items');
      expect(call.request.queryParameters, {'page': '2'});
      expect(call.loading, isTrue);

      samseer.recordWebViewEvent({
        'kind': 'res',
        'cid': 'cid-1',
        'status': 200,
        'headers': {'content-type': 'application/json'},
        'body': '[]',
      });

      call = samseer.calls.first;
      expect(call.response?.status, 200);
      // application/json responses are now parsed (previously left as the
      // raw '[]' string) so JSON bodies get the same tree/curl/copy
      // treatment across every transport, including the WebView bridge.
      expect(call.response?.body, <dynamic>[]);
      expect(call.state, SamseerCallState.success);

      // Late events for the same cid are ignored (id mapping cleared).
      samseer.recordWebViewEvent({
        'kind': 'res',
        'cid': 'cid-1',
        'status': 500,
      });
      expect(samseer.calls.first.response?.status, 200);
    });

    test('recordWebViewEvent ignores malformed payloads', () {
      final samseer = Samseer(
        configuration: const SamseerConfiguration(showInspectorOnShake: false),
      );
      addTearDown(samseer.dispose);

      samseer.recordWebViewEvent(null);
      samseer.recordWebViewEvent('not a map');
      samseer.recordWebViewEvent({'kind': 'req'}); // missing cid
      samseer.recordWebViewEvent({'cid': 'c'}); // missing kind

      expect(samseer.calls, isEmpty);
    });
  });
}
