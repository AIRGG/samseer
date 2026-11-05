import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../core/samseer_core.dart';
import '../../feature/exporter.dart';
import '../../model/http_call.dart';
import '../theme/samseer_theme.dart';
import '../widget/body_viewer.dart';
import '../widget/key_value_table.dart';
import '../widget/samseer_toast.dart';
import '../widget/status_badge.dart';

class CallDetailScreen extends StatelessWidget {
  const CallDetailScreen({super.key, required this.core, required this.callId});
  final SamseerCore core;
  final int callId;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<SamseerHttpCall>>(
      stream: core.storage.stream,
      initialData: core.storage.calls,
      builder: (context, snap) {
        final call = (snap.data ?? const <SamseerHttpCall>[]).firstWhere(
          (c) => c.id == callId,
          orElse: () => core.storage.findById(callId)!,
        );
        return DefaultTabController(
          length: 4,
          child: Theme(
            data: SamseerTheme.theme(),
            child: Scaffold(
              appBar: AppBar(
                title: Row(
                  children: [
                    MethodBadge(method: call.method),
                    const SizedBox(width: 8),
                    StatusBadge(
                        call: call, heroTag: 'samseer.status.${call.id}'),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        call.endpoint,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                actions: [
                  IconButton(
                    tooltip: 'Copy request & response',
                    icon: const Icon(Icons.content_copy_outlined),
                    onPressed: () => _copyDump(context, call),
                  ),
                ],
                bottom: const TabBar(
                  tabs: [
                    Tab(text: 'Overview'),
                    Tab(text: 'Request'),
                    Tab(text: 'Response'),
                    Tab(text: 'cURL'),
                  ],
                ),
              ),
              body: TabBarView(
                children: [
                  _OverviewTab(call: call),
                  _RequestTab(call: call),
                  _ResponseTab(call: call),
                  _CurlTab(call: call),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _copyDump(BuildContext context, SamseerHttpCall call) async {
    final dump = Exporter.buildCallDump(call);
    await Clipboard.setData(ClipboardData(text: dump));
    if (!context.mounted) return;
    final size = Exporter.formatSize(dump.length);
    final large = dump.length > 1024 * 1024;
    SamseerToast.show(
      context,
      large ? 'Copied — large content ($size)' : 'Copied to clipboard',
      subtitle: large
          ? 'Some apps may truncate. Consider saving to a file.'
          : 'Request & response · $size',
      variant:
          large ? SamseerToastVariant.warning : SamseerToastVariant.success,
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: cs.primary,
              letterSpacing: 1,
            ),
          ),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: child,
        ),
      ],
    );
  }
}

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({required this.call});
  final SamseerHttpCall call;

  @override
  Widget build(BuildContext context) {
    final entries = <String, dynamic>{
      'URL': call.uri,
      'Method': call.method,
      'Client': call.client,
      'Status': call.response?.status ?? (call.hasError ? 'ERROR' : 'pending'),
      'Started': DateFormat('yyyy-MM-dd HH:mm:ss.SSS').format(call.createdAt),
      'Duration': _fmtDuration(call.duration),
      'Request Size': _fmtBytes(call.request.size),
      'Response Size': _fmtBytes(call.response?.size),
      'Secure': call.secure ? 'TLS' : 'plain',
    };
    return ListView(
      children: [
        _Section(title: 'Summary', child: KeyValueTable(entries: entries)),
        if (call.error != null)
          _Section(
            title: 'Error',
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: SelectableText(
                call.error?.message ??
                    call.error?.error?.toString() ??
                    'Unknown error',
                style:
                    SamseerTheme.mono(context, color: const Color(0xFFEF4444)),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: FilledButton.icon(
            icon: const Icon(Icons.copy),
            label: const Text('Copy URL'),
            onPressed: () async {
              final text = '${call.method.toUpperCase()} ${call.uri}';
              await Clipboard.setData(ClipboardData(text: text));
              if (!context.mounted) return;
              SamseerToast.show(
                context,
                'URL copied',
                subtitle: '${call.method.toUpperCase()} ${call.endpoint}',
                variant: SamseerToastVariant.success,
              );
            },
          ),
        ),
      ],
    );
  }

  String _fmtDuration(Duration? d) {
    if (d == null) return '—';
    final ms = d.inMilliseconds;
    return ms < 1000 ? '${ms}ms' : '${(ms / 1000).toStringAsFixed(2)}s';
  }

  String _fmtBytes(int? b) {
    if (b == null) return '—';
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
    return '${(b / 1024 / 1024).toStringAsFixed(2)} MB';
  }
}

class _RequestTab extends StatelessWidget {
  const _RequestTab({required this.call});
  final SamseerHttpCall call;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        _Section(
          title: 'Headers',
          child: KeyValueTable(
              entries: call.request.headers, emptyLabel: 'No headers'),
        ),
        _Section(
          title: 'Query Parameters',
          child: KeyValueTable(
            entries: call.request.queryParameters,
            emptyLabel: 'No query parameters',
          ),
        ),
        _Section(
          title: 'Body',
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: call.request.body == null
                ? Text(
                    'No body',
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                  )
                : BodyViewer(
                    body: call.request.body,
                    contentType: call.request.contentType,
                  ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: FilledButton.icon(
            icon: const Icon(Icons.copy),
            label: const Text('Copy Request Body'),
            onPressed: call.request.body == null
                ? null
                : () async {
                    final body = Exporter.buildRequestBody(call)!;
                    await Clipboard.setData(ClipboardData(text: body));
                    if (!context.mounted) return;
                    SamseerToast.show(
                      context,
                      'Request body copied',
                      subtitle: Exporter.formatSize(body.length),
                      variant: SamseerToastVariant.success,
                    );
                  },
          ),
        ),
      ],
    );
  }
}

class _ResponseTab extends StatelessWidget {
  const _ResponseTab({required this.call});
  final SamseerHttpCall call;

  @override
  Widget build(BuildContext context) {
    if (call.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final response = call.response;
    if (response == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            call.error?.message ?? 'No response received',
            style: const TextStyle(color: Color(0xFFEF4444)),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return ListView(
      children: [
        _Section(
          title: 'Headers',
          child: KeyValueTable(
              entries: response.headers, emptyLabel: 'No headers'),
        ),
        _Section(
          title: 'Body',
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: response.body == null
                ? Text(
                    'No body',
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                  )
                : BodyViewer(
                    body: response.body,
                    contentType: response.contentType,
                  ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: FilledButton.icon(
            icon: const Icon(Icons.copy),
            label: const Text('Copy Response Body'),
            onPressed: call.response?.body == null
                ? null
                : () async {
                    final body = Exporter.buildResponseBody(call)!;
                    await Clipboard.setData(ClipboardData(text: body));
                    if (!context.mounted) return;
                    SamseerToast.show(
                      context,
                      'Response body copied',
                      subtitle: Exporter.formatSize(body.length),
                      variant: SamseerToastVariant.success,
                    );
                  },
          ),
        ),
      ],
    );
  }
}

class _CurlTab extends StatelessWidget {
  const _CurlTab({required this.call});
  final SamseerHttpCall call;

  @override
  Widget build(BuildContext context) {
    final curl = Exporter.buildCurl(call);
    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(14),
            ),
            child: SelectableText(curl, style: SamseerTheme.mono(context)),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: FilledButton.icon(
            icon: const Icon(Icons.copy),
            label: const Text('Copy cURL'),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: curl));
              if (!context.mounted) return;
              SamseerToast.show(
                context,
                'cURL copied',
                subtitle: Exporter.formatSize(curl.length),
                variant: SamseerToastVariant.success,
              );
            },
          ),
        ),
      ],
    );
  }
}
