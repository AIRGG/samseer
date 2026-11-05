import 'package:flutter/material.dart';

import '../feature/shake_detector.dart';
import '../model/http_call.dart';
import '../model/http_error.dart';
import '../model/http_request.dart';
import '../model/http_response.dart';
import '../ui/screen/call_list_screen.dart';
import 'samseer_configuration.dart';
import 'samseer_storage.dart';

/// Internal controller. Public users interact with [Samseer], not this.
class SamseerCore {
  SamseerCore({SamseerConfiguration? configuration})
      : configuration = configuration ?? const SamseerConfiguration() {
    storage = SamseerStorage(maxCallsCount: this.configuration.maxCallsCount);
    if (this.configuration.showInspectorOnShake) {
      _shakeDetector = ShakeDetector(
        threshold: this.configuration.shakeThreshold,
        onShake: openInspector,
      );
      // Defer start until the Flutter binding is initialized. Allows
      // callers to construct Samseer before runApp() / ensureInitialized().
      Future<void>.microtask(() => _shakeDetector?.start());
    }
  }

  final SamseerConfiguration configuration;
  late final SamseerStorage storage;
  ShakeDetector? _shakeDetector;

  final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>(debugLabel: 'samseer.navigatorKey');

  /// True while any samseer screen is on top of the navigator stack.
  /// UI overlays (e.g. floating bubble) can listen to this to hide
  /// themselves while the user is already inside the inspector.
  final ValueNotifier<bool> inspectorOpen = ValueNotifier<bool>(false);

  int _idSeed = 0;
  int nextId() => ++_idSeed;

  void addCall(SamseerHttpCall call) => storage.addCall(call);

  void updateRequest(int id, SamseerHttpRequest request) =>
      storage.updateRequest(id, request);

  void addResponse(int id, SamseerHttpResponse response) =>
      storage.updateResponse(id, response);

  void addError(int id, SamseerHttpError error) =>
      storage.updateError(id, error);

  /// Open the inspector. Requires that [navigatorKey] is attached to the
  /// host [MaterialApp.navigatorKey].
  Future<void> openInspector() async {
    if (inspectorOpen.value) return;
    final state = navigatorKey.currentState;
    if (state == null) return;
    inspectorOpen.value = true;
    try {
      await state.push(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: kCallListRoute),
          builder: (_) => CallListScreen(core: this),
        ),
      );
    } finally {
      inspectorOpen.value = false;
    }
  }

  /// Open the inspector against a known [BuildContext].
  Future<void> openInspectorFromContext(BuildContext context) async {
    if (inspectorOpen.value) return;
    inspectorOpen.value = true;
    try {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: kCallListRoute),
          builder: (_) => CallListScreen(core: this),
        ),
      );
    } finally {
      inspectorOpen.value = false;
    }
  }

  void dispose() {
    _shakeDetector?.stop();
    inspectorOpen.dispose();
    storage.dispose();
  }
}

const String kCallListRoute = 'samseer.callList';
