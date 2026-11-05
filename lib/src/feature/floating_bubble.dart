import 'package:flutter/material.dart';

import '../core/samseer_core.dart';
import '../model/console_log.dart';
import '../model/http_call.dart';

/// A draggable floating bubble overlay that shows a live count of everything
/// recorded: HTTP calls plus console entries. Tapping it opens the inspector.
///
/// Place [SamseerOverlay] near the top of your widget tree (e.g. via
/// [MaterialApp.builder]).
class SamseerOverlay extends StatefulWidget {
  const SamseerOverlay({
    super.key,
    required this.core,
    required this.child,
  });

  final SamseerCore core;
  final Widget child;

  @override
  State<SamseerOverlay> createState() => _SamseerOverlayState();
}

class _SamseerOverlayState extends State<SamseerOverlay> {
  Offset _offset = const Offset(16, 200);
  bool _initialized = false;

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      final size = MediaQuery.of(context).size;
      _offset = Offset(size.width - 80, size.height * 0.35);
      _initialized = true;
    }
    return Stack(
      children: [
        widget.child,
        ValueListenableBuilder<bool>(
          valueListenable: widget.core.inspectorOpen,
          builder: (context, isOpen, _) {
            if (isOpen) return const SizedBox.shrink();
            return Positioned(
              left: _offset.dx,
              top: _offset.dy,
              child: GestureDetector(
                onPanUpdate: (d) => setState(() => _offset += d.delta),
                onTap: widget.core.openInspector,
                child: StreamBuilder<List<SamseerHttpCall>>(
                  stream: widget.core.storage.stream,
                  initialData: widget.core.storage.calls,
                  builder: (context, callSnap) {
                    return StreamBuilder<List<SamseerConsoleLog>>(
                      stream: widget.core.storage.consoleStream,
                      initialData: widget.core.storage.consoleLogs,
                      builder: (context, logSnap) {
                        final count = (callSnap.data?.length ?? 0) +
                            (logSnap.data?.length ?? 0);
                        return _Bubble(count: count);
                      },
                    );
                  },
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 8,
      shape: const StadiumBorder(),
      color: Theme.of(context).colorScheme.primary,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.travel_explore,
              size: 18,
              color: Theme.of(context).colorScheme.onPrimary,
            ),
            const SizedBox(width: 6),
            Text(
              '$count',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
