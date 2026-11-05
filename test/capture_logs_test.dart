import 'package:flutter_test/flutter_test.dart';
import 'package:samseer/samseer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('captureLogs records print as an app log entry', () {
    final samseer = Samseer(
      configuration: const SamseerConfiguration(showInspectorOnShake: false),
    );
    samseer.captureLogs(() {
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
}
