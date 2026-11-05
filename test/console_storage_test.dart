import 'package:flutter_test/flutter_test.dart';
import 'package:samseer/samseer.dart';
import 'package:samseer/src/core/samseer_storage.dart';
import 'package:samseer/src/model/console_log.dart'
    show samseerLogLevelFromString;

void main() {
  SamseerConsoleLog log(int id, {SamseerLogLevel level = SamseerLogLevel.log}) {
    return SamseerConsoleLog(
      id: id,
      level: level,
      source: SamseerLogSource.app,
      message: 'msg $id',
      time: DateTime.now(),
    );
  }

  group('SamseerConfiguration console fields', () {
    test('defaults', () {
      const config = SamseerConfiguration();
      expect(config.maxConsoleLogsCount, 500);
      expect(config.captureNetworkErrorsInConsole, true);
    });

    test('copyWith preserves console fields', () {
      const config = SamseerConfiguration(maxConsoleLogsCount: 10);
      final next = config.copyWith(captureNetworkErrorsInConsole: false);
      expect(next.maxConsoleLogsCount, 10);
      expect(next.captureNetworkErrorsInConsole, false);
    });
  });

  group('samseerLogLevelFromString', () {
    test('maps known levels', () {
      expect(samseerLogLevelFromString('info'), SamseerLogLevel.info);
      expect(samseerLogLevelFromString('warn'), SamseerLogLevel.warn);
      expect(samseerLogLevelFromString('warning'), SamseerLogLevel.warn);
      expect(samseerLogLevelFromString('error'), SamseerLogLevel.error);
      expect(samseerLogLevelFromString('debug'), SamseerLogLevel.debug);
    });

    test('unknown falls back to log', () {
      expect(samseerLogLevelFromString('verbose'), SamseerLogLevel.log);
      expect(samseerLogLevelFromString(null), SamseerLogLevel.log);
    });
  });

  group('SamseerStorage console buffer', () {
    test('addConsoleLog keeps newest first and caps at max', () {
      final storage = SamseerStorage(maxConsoleLogsCount: 3);
      for (var i = 1; i <= 5; i++) {
        storage.addConsoleLog(log(i));
      }
      expect(storage.consoleLogs.map((l) => l.id), [5, 4, 3]);
      storage.dispose();
    });

    test('clear empties both calls and console buffers', () {
      final storage = SamseerStorage();
      storage.addConsoleLog(log(1));
      storage.clear();
      expect(storage.consoleLogs, isEmpty);
      storage.dispose();
    });

    test('consoleStream emits on add', () async {
      final storage = SamseerStorage();
      final future = storage.consoleStream.first;
      storage.addConsoleLog(log(1));
      final emitted = await future;
      expect(emitted.single.id, 1);
      storage.dispose();
    });
  });
}
