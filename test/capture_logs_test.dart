import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:samseer/samseer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('captureLogs records print as an app log entry', () {
    final samseer = Samseer(
      configuration: const SamseerConfiguration(showInspectorOnShake: false),
    );
    samseer.captureLogs(() {
      // ignore: avoid_print
      print('hello from app');
    });
    final logs = samseer.consoleLogs;
    expect(logs, hasLength(1));
    expect(logs.single.message, 'hello from app');
    expect(logs.single.level, SamseerLogLevel.log);
    expect(logs.single.source, SamseerLogSource.app);
    samseer.dispose();
  });

  test('captureLogs returns the body result', () {
    final samseer = Samseer(
      configuration: const SamseerConfiguration(showInspectorOnShake: false),
    );
    final result = samseer.captureLogs<int>(() => 42);
    expect(result, 42);
    samseer.dispose();
  });

  test('captureLogs records uncaught async zone errors', () async {
    final samseer = Samseer(
      configuration: const SamseerConfiguration(showInspectorOnShake: false),
    );
    samseer.captureLogs(() {
      Future<void>.error(StateError('async boom'));
    });
    // Let the microtask/event queue flush.
    await Future<void>.delayed(const Duration(milliseconds: 10));
    final errors = samseer.consoleLogs
        .where((l) => l.level == SamseerLogLevel.error)
        .toList();
    expect(errors, isNotEmpty);
    expect(errors.first.message, contains('async boom'));
    expect(errors.first.source, SamseerLogSource.app);
    samseer.dispose();
  });
  test('uncaught zone errors are still printed to the outer zone', () async {
    final samseer = Samseer(
      configuration: const SamseerConfiguration(showInspectorOnShake: false),
    );
    final printed = <String>[];
    runZoned(
      () => samseer.captureLogs(() {
        Future<void>.error(StateError('visible boom'));
      }),
      zoneSpecification: ZoneSpecification(
        print: (self, parent, zone, line) => printed.add(line),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(printed.join('\n'), contains('visible boom'));
    samseer.dispose();
  });

  group('chained global handlers', () {
    late FlutterExceptionHandler? savedFlutterOnError;
    late bool Function(Object, StackTrace)? savedPlatformOnError;

    setUp(() {
      savedFlutterOnError = FlutterError.onError;
      savedPlatformOnError = PlatformDispatcher.instance.onError;
    });

    tearDown(() {
      FlutterError.onError = savedFlutterOnError;
      PlatformDispatcher.instance.onError = savedPlatformOnError;
    });

    test('framework error dump lines are not captured as log entries', () {
      final samseer = Samseer(
        configuration: const SamseerConfiguration(showInspectorOnShake: false),
      );
      FlutterError.onError = (details) {
        // Simulates dumpErrorToConsole printing many lines.
        for (var i = 0; i < 5; i++) {
          // ignore: avoid_print
          print('══╡ dump line $i');
        }
      };
      samseer.captureLogs(() {
        FlutterError.onError!(
          FlutterErrorDetails(exception: StateError('overflow')),
        );
      });
      final logs = samseer.consoleLogs;
      expect(logs, hasLength(1));
      expect(logs.single.level, SamseerLogLevel.error);
      expect(logs.single.message, contains('overflow'));
      samseer.dispose();
    });

    test('existing PlatformDispatcher.onError keeps running', () {
      final samseer = Samseer(
        configuration: const SamseerConfiguration(showInspectorOnShake: false),
      );
      Object? seenByPrevious;
      PlatformDispatcher.instance.onError = (error, stack) {
        seenByPrevious = error;
        return true;
      };
      samseer.captureLogs(() {});
      final handled = PlatformDispatcher.instance.onError!(
        StateError('crashlytics sees me'),
        StackTrace.current,
      );
      expect(handled, isTrue);
      expect(seenByPrevious, isA<StateError>());
      expect(samseer.consoleLogs.single.message, contains('crashlytics'));
      samseer.dispose();
    });
  });
}
