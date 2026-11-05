import 'dart:async';
import 'dart:collection';

import '../model/console_log.dart';
import '../model/http_call.dart';
import '../model/http_error.dart';
import '../model/http_request.dart';
import '../model/http_response.dart';

/// In-memory storage for [SamseerHttpCall]s with a reactive stream.
class SamseerStorage {
  SamseerStorage({this.maxCallsCount = 1000, this.maxConsoleLogsCount = 500});

  final int maxCallsCount;
  final int maxConsoleLogsCount;
  final Queue<SamseerHttpCall> _calls = Queue<SamseerHttpCall>();
  final Queue<SamseerConsoleLog> _logs = Queue<SamseerConsoleLog>();
  final StreamController<List<SamseerHttpCall>> _controller =
      StreamController<List<SamseerHttpCall>>.broadcast();
  final StreamController<List<SamseerConsoleLog>> _logController =
      StreamController<List<SamseerConsoleLog>>.broadcast();

  /// Reactive stream emitted on every change. Latest snapshot wins.
  Stream<List<SamseerHttpCall>> get stream => _controller.stream;

  /// Synchronous snapshot of all calls, newest first.
  List<SamseerHttpCall> get calls => _calls.toList(growable: false);

  /// Reactive stream of console entries. Latest snapshot wins.
  Stream<List<SamseerConsoleLog>> get consoleStream => _logController.stream;

  /// Synchronous snapshot of all console entries, newest first.
  List<SamseerConsoleLog> get consoleLogs => _logs.toList(growable: false);

  void addCall(SamseerHttpCall call) {
    _calls.addFirst(call);
    while (_calls.length > maxCallsCount) {
      _calls.removeLast();
    }
    _emit();
  }

  void addConsoleLog(SamseerConsoleLog log) {
    _logs.addFirst(log);
    while (_logs.length > maxConsoleLogsCount) {
      _logs.removeLast();
    }
    _emitLogs();
  }

  void updateRequest(int id, SamseerHttpRequest request) {
    _replace(id, (c) => c.copyWith(request: request));
  }

  void updateResponse(int id, SamseerHttpResponse response) {
    _replace(id, (c) => c.copyWith(response: response));
  }

  void updateError(int id, SamseerHttpError error) {
    _replace(id, (c) => c.copyWith(error: error));
  }

  void clear() {
    _calls.clear();
    _logs.clear();
    _emit();
    _emitLogs();
  }

  SamseerHttpCall? findById(int id) {
    for (final c in _calls) {
      if (c.id == id) return c;
    }
    return null;
  }

  void dispose() {
    _controller.close();
    _logController.close();
  }

  void _replace(int id, SamseerHttpCall Function(SamseerHttpCall) update) {
    final list = _calls.toList();
    final index = list.indexWhere((c) => c.id == id);
    if (index == -1) return;
    list[index] = update(list[index]);
    _calls
      ..clear()
      ..addAll(list);
    _emit();
  }

  void _emit() {
    if (_controller.isClosed) return;
    _controller.add(_calls.toList(growable: false));
  }

  void _emitLogs() {
    if (_logController.isClosed) return;
    _logController.add(_logs.toList(growable: false));
  }
}
