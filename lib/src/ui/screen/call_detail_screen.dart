import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../core/samseer_core.dart';
import '../../feature/exporter.dart';
import '../../feature/text_export.dart';
import '../../model/http_call.dart';
import '../text/body_document.dart';
import '../theme/samseer_theme.dart';
import '../widget/body_viewer.dart';
import '../widget/document_view.dart';
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
        final limit = core.configuration.effectiveCopyLimitBytes;
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
                  _RequestTab(call: call, limitBytes: limit),
                  _ResponseTab(call: call, limitBytes: limit),
                  _CurlTab(call: call, limitBytes: limit),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _copyDump(BuildContext context, SamseerHttpCall call) {
    return copyOrDownloadText(
      context,
      text: Exporter.buildCallDump(call),
      fileName: buildExportFileName(
        part: 'call',
        method: call.method,
        endpoint: call.endpoint,
        time: call.createdAt,
      ),
      copiedTitle: 'Request & response copied',
      limitBytes: core.configuration.effectiveCopyLimitBytes,
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

/// Document builders live at top level so the closures handed to
/// [loadBodyDocument] capture only sendable values (never a widget, State or
/// BuildContext), since they run in another isolate.
BodyDocument Function() _bodyDocumentBuilder(
  dynamic body,
  String? contentType,
) =>
    () => documentFromBody(body, contentType: contentType);

BodyDocument Function() _curlDocumentBuilder(SamseerHttpCall call) {
  // Only what buildCurl reads; the response and error stay on this isolate.
  final stripped = SamseerHttpCall(
    id: call.id,
    method: call.method,
    uri: call.uri,
    endpoint: call.endpoint,
    server: call.server,
    secure: call.secure,
    client: call.client,
    createdAt: call.createdAt,
    request: call.request,
  );
  return () =>
      documentFromText(Exporter.buildCurl(stripped), highlightJson: false);
}

/// Whether a body is small enough to rebuild on the UI thread when the
/// background build failed.
bool _smallBody(dynamic body, int? size) {
  if (body is String) return body.length <= kCopyLimitBytes;
  return size != null && size <= kCopyLimitBytes;
}

BodyDocument? _tryBuild(bool small, BodyDocument Function() build) {
  if (!small) return null;
  try {
    return build();
  } catch (_) {
    return null;
  }
}

/// Body section for bodies that skip the text viewer: "No body", or the
/// binary, multipart and CSV viewers as before.
class _PlainBodyTab extends StatelessWidget {
  const _PlainBodyTab({
    required this.header,
    required this.body,
    required this.contentType,
    required this.copyLabel,
    required this.fileName,
    required this.copiedTitle,
    required this.limitBytes,
  });

  final List<Widget> header;
  final dynamic body;
  final String? contentType;
  final String copyLabel;
  final String fileName;
  final String copiedTitle;
  final int limitBytes;

  @override
  Widget build(BuildContext context) {
    final value = body;
    return BodyScrollLayout(
      slivers: [
        ...header,
        SliverToBoxAdapter(
          child: _Section(
            title: 'Body',
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: value == null
                  ? Text(
                      'No body',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    )
                  : BodyViewer(body: value, contentType: contentType),
            ),
          ),
        ),
      ],
      button: FilledButton.icon(
        icon: const Icon(Icons.copy),
        label: Text(copyLabel),
        onPressed: value == null
            ? null
            : () => copyOrDownloadText(
                context,
                text: Exporter.formatBody(value, contentType: contentType),
                fileName: fileName,
                copiedTitle: copiedTitle,
                limitBytes: limitBytes,
              ),
      ),
    );
  }
}

class _RequestTab extends StatelessWidget {
  const _RequestTab({required this.call, required this.limitBytes});
  final SamseerHttpCall call;
  final int limitBytes;

  @override
  Widget build(BuildContext context) {
    final request = call.request;
    final body = request.body;
    final contentType = request.contentType;
    final size = request.size;
    final fileName = buildExportFileName(
      part: 'request',
      method: call.method,
      endpoint: call.endpoint,
      time: call.createdAt,
    );
    final header = <Widget>[
      SliverToBoxAdapter(
        child: _Section(
          title: 'Headers',
          child: KeyValueTable(
            entries: request.headers,
            emptyLabel: 'No headers',
          ),
        ),
      ),
      SliverToBoxAdapter(
        child: _Section(
          title: 'Query Parameters',
          child: KeyValueTable(
            entries: request.queryParameters,
            emptyLabel: 'No query parameters',
          ),
        ),
      ),
    ];
    if (body == null || !usesTextViewer(body, contentType)) {
      return _PlainBodyTab(
        header: header,
        body: body,
        contentType: contentType,
        copyLabel: 'Copy Request Body',
        fileName: fileName,
        copiedTitle: 'Request body copied',
        limitBytes: limitBytes,
      );
    }
    final build = _bodyDocumentBuilder(body, contentType);
    return DocumentView(
      header: header,
      title: 'BODY',
      future: loadBodyDocument(request, 'body', build),
      fallback: () => _tryBuild(_smallBody(body, size), build),
      copyLabel: 'Copy Request Body',
      fileName: fileName,
      copiedTitle: 'Request body copied',
      limitBytes: limitBytes,
    );
  }
}

class _ResponseTab extends StatelessWidget {
  const _ResponseTab({required this.call, required this.limitBytes});
  final SamseerHttpCall call;
  final int limitBytes;

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
    final body = response.body;
    final contentType = response.contentType;
    final size = response.size;
    final fileName = buildExportFileName(
      part: 'response',
      method: call.method,
      endpoint: call.endpoint,
      time: call.createdAt,
    );
    final header = <Widget>[
      SliverToBoxAdapter(
        child: _Section(
          title: 'Headers',
          child: KeyValueTable(
            entries: response.headers,
            emptyLabel: 'No headers',
          ),
        ),
      ),
    ];
    if (body == null || !usesTextViewer(body, contentType)) {
      return _PlainBodyTab(
        header: header,
        body: body,
        contentType: contentType,
        copyLabel: 'Copy Response Body',
        fileName: fileName,
        copiedTitle: 'Response body copied',
        limitBytes: limitBytes,
      );
    }
    final build = _bodyDocumentBuilder(body, contentType);
    return DocumentView(
      header: header,
      title: 'BODY',
      future: loadBodyDocument(response, 'body', build),
      fallback: () => _tryBuild(_smallBody(body, size), build),
      copyLabel: 'Copy Response Body',
      fileName: fileName,
      copiedTitle: 'Response body copied',
      limitBytes: limitBytes,
    );
  }
}

class _CurlTab extends StatelessWidget {
  const _CurlTab({required this.call, required this.limitBytes});
  final SamseerHttpCall call;
  final int limitBytes;

  @override
  Widget build(BuildContext context) {
    final request = call.request;
    final build = _curlDocumentBuilder(call);
    return DocumentView(
      future: loadBodyDocument(request, 'curl', build),
      fallback: () => _tryBuild(_smallBody(request.body, request.size), build),
      copyLabel: 'Copy cURL',
      fileName: buildExportFileName(
        part: 'curl',
        method: call.method,
        endpoint: call.endpoint,
        time: call.createdAt,
      ),
      copiedTitle: 'cURL copied',
      limitBytes: limitBytes,
    );
  }
}
