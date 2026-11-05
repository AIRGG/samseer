import 'dart:convert';

import '../model/content_kind.dart';
import '../model/http_body.dart';
import '../model/http_call.dart';
import '../util/xml_format.dart';

class Exporter {
  /// Build a pretty-printed JSON array of every call — suitable for clipboard
  /// or paste-into-file workflows.
  static String buildJsonExport(List<SamseerHttpCall> calls) {
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(calls.map((c) => c.toJson()).toList());
  }

  /// Build a complete, paste-ready dump of the call: URL, method, status,
  /// timing, request headers/body, response headers/body, and cURL command.
  /// Format is plain text — friendly for Slack, Discord, GitHub issues.
  static String buildCallDump(SamseerHttpCall call) {
    final b = StringBuffer();
    const encoder = JsonEncoder.withIndent('  ');

    b
      ..writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━')
      ..writeln('  ${call.method} ${call.uri}')
      ..writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━')
      ..writeln('Client      : ${call.client}')
      ..writeln(
          'Status      : ${call.response?.status ?? (call.hasError ? "ERROR" : "pending")}')
      ..writeln('Duration    : ${_fmtDuration(call.duration)}')
      ..writeln('Started     : ${call.createdAt.toIso8601String()}')
      ..writeln('Secure      : ${call.secure ? "TLS" : "plain"}')
      ..writeln();

    b.writeln('── REQUEST ──────────────────────────────────');
    if (call.request.queryParameters.isNotEmpty) {
      b.writeln('Query:');
      call.request.queryParameters.forEach((k, v) => b.writeln('  $k = $v'));
    }
    if (call.request.headers.isNotEmpty) {
      b.writeln('Headers:');
      call.request.headers.forEach((k, v) => b.writeln('  $k: $v'));
    }
    if (call.request.body != null) {
      b
        ..writeln('Body:')
        ..writeln(_formatBody(call.request.body, encoder,
            contentType: call.request.contentType));
    }
    b.writeln();

    b.writeln('── RESPONSE ─────────────────────────────────');
    final response = call.response;
    if (response == null && call.error != null) {
      b
        ..writeln(
            'Error: ${call.error?.message ?? call.error?.error ?? "unknown"}')
        ..writeln();
    } else if (response != null) {
      b.writeln('Status: ${response.status}');
      if (response.headers.isNotEmpty) {
        b.writeln('Headers:');
        response.headers.forEach((k, v) => b.writeln('  $k: $v'));
      }
      if (response.body != null) {
        b
          ..writeln('Body:')
          ..writeln(_formatBody(response.body, encoder,
              contentType: response.contentType));
      }
      b.writeln();
    } else {
      b.writeln('(no response yet)');
    }

    b
      ..writeln('── cURL ─────────────────────────────────────')
      ..writeln(buildCurl(call));

    return b.toString();
  }

  /// Returns the request body as a formatted string, or null if there is none.
  static String? buildRequestBody(SamseerHttpCall call) {
    if (call.request.body == null) return null;
    const encoder = JsonEncoder.withIndent('  ');
    return _formatBody(call.request.body, encoder,
        contentType: call.request.contentType);
  }

  /// Returns the response body as a formatted string, or null if there is none.
  static String? buildResponseBody(SamseerHttpCall call) {
    final body = call.response?.body;
    if (body == null) return null;
    const encoder = JsonEncoder.withIndent('  ');
    return _formatBody(body, encoder, contentType: call.response?.contentType);
  }

  /// Build a cURL representation of the given call. `multipart/form-data`
  /// bodies become `-F` flags (file parts reference `@filename` even though
  /// the file itself was never captured — this documents intent the same
  /// way browser/Postman "copy as cURL" does). Binary bodies can't be
  /// embedded safely inline, so they're left as a comment describing size
  /// and type instead of a `-d` flag.
  static String buildCurl(SamseerHttpCall call) {
    final buffer = StringBuffer('curl -X ${call.method.toUpperCase()}');
    call.request.headers.forEach((key, value) {
      buffer.write(" -H '${_escape('$key: $value')}'");
    });
    final body = call.request.body;
    if (body is SamseerMultipartBody) {
      body.fields.forEach((k, v) {
        buffer.write(" -F '${_escape('$k=$v')}'");
      });
      for (final f in body.files) {
        final type = f.contentType != null ? ';type=${f.contentType}' : '';
        buffer
            .write(" -F '${_escape('${f.field}=@${f.filename ?? 'file'}$type')}'");
      }
    } else if (body is SamseerBinaryBody) {
      buffer.write(
          " \\\n  # binary body omitted (${body.contentType ?? 'unknown type'}, ${formatSize(body.totalSize)})");
    } else if (body is Map &&
        classifyContentType(call.request.contentType) ==
            SamseerBodyKind.formUrlEncoded) {
      buffer.write(" -d '${_escape(_encodeFormUrlEncoded(body))}'");
    } else if (body != null) {
      final encoded = body is String ? body : json.encode(body);
      buffer.write(" -d '${_escape(encoded)}'");
    }
    buffer.write(" '${call.uri}'");
    return buffer.toString();
  }

  /// Human-readable byte size — used by callers to show "Copied (12.4 KB)".
  static String formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(2)} MB';
  }

  static String _formatBody(
    dynamic body,
    JsonEncoder encoder, {
    String? contentType,
  }) {
    if (body == null) return '';
    if (body is SamseerBinaryBody) {
      final type = body.contentType ?? contentType ?? 'unknown type';
      final note =
          body.truncated ? ' — not retained in memory (too large)' : '';
      return '<binary body: ${formatSize(body.totalSize)}, $type$note>';
    }
    if (body is SamseerMultipartBody) {
      return _formatMultipart(body);
    }
    final kind = classifyContentType(contentType);
    if (body is Map && kind == SamseerBodyKind.formUrlEncoded) {
      return _encodeFormUrlEncoded(body);
    }
    if (body is Map || body is List) {
      try {
        return encoder.convert(body);
      } catch (_) {
        return body.toString();
      }
    }
    if (body is String) {
      if (kind == SamseerBodyKind.xml) {
        return prettyPrintXml(body);
      }
      final trimmed = body.trim();
      if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
        try {
          return encoder.convert(json.decode(trimmed));
        } catch (_) {}
      }
      return body;
    }
    return body.toString();
  }

  static String _formatMultipart(SamseerMultipartBody body) {
    final b = StringBuffer();
    if (body.fields.isNotEmpty) {
      b.writeln('fields:');
      body.fields.forEach((k, v) => b.writeln('  $k = $v'));
    }
    if (body.files.isNotEmpty) {
      if (body.fields.isNotEmpty) b.writeln();
      b.writeln('files:');
      for (final f in body.files) {
        final meta = [
          if (f.contentType != null) f.contentType!,
          if (f.length != null) formatSize(f.length!),
        ].join(', ');
        b.writeln(
            '  ${f.field}: ${f.filename ?? '(no filename)'}${meta.isNotEmpty ? ' ($meta)' : ''}');
      }
    }
    return b.toString().trimRight();
  }

  static String _encodeFormUrlEncoded(Map body) {
    return body.entries
        .map((e) =>
            '${Uri.encodeQueryComponent('${e.key}')}=${Uri.encodeQueryComponent('${e.value}')}')
        .join('&');
  }

  static String _escape(String s) => s.replaceAll("'", "'\\''");

  static String _fmtDuration(Duration? d) {
    if (d == null) return '—';
    final ms = d.inMilliseconds;
    if (ms < 1000) return '${ms}ms';
    return '${(ms / 1000).toStringAsFixed(2)}s';
  }
}
