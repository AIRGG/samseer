import 'package:flutter/foundation.dart';

import 'http_error.dart';
import 'http_request.dart';
import 'http_response.dart';

enum SamseerCallState {
  loading,
  success,
  redirect,
  clientError,
  serverError,
  error
}

@immutable
class SamseerHttpCall {
  const SamseerHttpCall({
    required this.id,
    required this.method,
    required this.uri,
    required this.endpoint,
    required this.server,
    required this.secure,
    required this.client,
    required this.createdAt,
    required this.request,
    this.response,
    this.error,
  });

  final int id;
  final String method;
  final String uri;
  final String endpoint;
  final String server;
  final bool secure;
  final String client;
  final DateTime createdAt;
  final SamseerHttpRequest request;
  final SamseerHttpResponse? response;
  final SamseerHttpError? error;

  bool get loading => response == null && error == null;
  bool get hasError => error != null;
  int? get status => response?.status;

  Duration? get duration {
    final responseTime = response?.time;
    if (responseTime != null) return responseTime.difference(request.time);
    final errorTime = error != null ? createdAt : null;
    return errorTime?.difference(request.time);
  }

  SamseerCallState get state {
    if (error != null) return SamseerCallState.error;
    final s = response?.status;
    if (s == null) return SamseerCallState.loading;
    if (s >= 200 && s < 300) return SamseerCallState.success;
    if (s >= 300 && s < 400) return SamseerCallState.redirect;
    if (s >= 400 && s < 500) return SamseerCallState.clientError;
    if (s >= 500) return SamseerCallState.serverError;
    return SamseerCallState.success;
  }

  SamseerHttpCall copyWith({
    SamseerHttpRequest? request,
    SamseerHttpResponse? response,
    SamseerHttpError? error,
  }) {
    return SamseerHttpCall(
      id: id,
      method: method,
      uri: uri,
      endpoint: endpoint,
      server: server,
      secure: secure,
      client: client,
      createdAt: createdAt,
      request: request ?? this.request,
      response: response ?? this.response,
      error: error ?? this.error,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'method': method,
        'uri': uri,
        'endpoint': endpoint,
        'server': server,
        'secure': secure,
        'client': client,
        'createdAt': createdAt.toIso8601String(),
        'request': request.toJson(),
        'response': response?.toJson(),
        'error': error?.toJson(),
        'durationMs': duration?.inMilliseconds,
      };
}
