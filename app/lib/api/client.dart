import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';
import 'sse.dart';

/// Error returned by the API (`{"error": {"code", "message"}}`) or a
/// transport failure (`code == 'network'`).
class ApiException implements Exception {
  const ApiException(this.code, {this.message, this.status, this.retryAfter});

  final String code;
  final String? message;
  final int? status;

  /// Set for `429 rate_limited` from the `Retry-After` header.
  final Duration? retryAfter;

  @override
  String toString() => 'ApiException($status $code: $message)';
}

class PravdomerClient {
  PravdomerClient({
    required this.baseUrl,
    required this.deviceId,
    http.Client? httpClient,
    this.reconnectDelay = const Duration(seconds: 1),
    this.maxConsecutiveFailures = 5,
    this.maxReconnects = 30,
  }) : _http = httpClient ?? http.Client();

  final Uri baseUrl;
  final String deviceId;
  final http.Client _http;
  final Duration reconnectDelay;
  final int maxConsecutiveFailures;
  final int maxReconnects;

  Map<String, String> get _headers => {'X-Device-Id': deviceId};

  Uri _uri(String path) => baseUrl.resolve(path);

  /// `POST /v1/analyses` with either [url] or [text].
  Future<StartResponse> createAnalysis({
    String? url,
    String? text,
    String? title,
  }) async {
    assert((url == null) != (text == null), 'exactly one of url/text');
    final body = <String, String>{
      'url': ?url,
      'text': ?text,
      if (title != null && title.isNotEmpty) 'title': title,
    };
    final http.Response resp;
    try {
      resp = await _http.post(
        _uri('/v1/analyses'),
        headers: {..._headers, 'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );
    } on Exception catch (e) {
      throw ApiException('network', message: e.toString());
    }
    if (resp.statusCode == 200 || resp.statusCode == 202) {
      final j = _decodeMap(utf8.decode(resp.bodyBytes));
      final start = StartResponse.fromJson(j ?? const {});
      if (start.id.isEmpty) {
        throw ApiException('internal', status: resp.statusCode);
      }
      return start;
    }
    throw _errorFrom(
      resp.statusCode,
      resp.headers,
      utf8.decode(resp.bodyBytes),
    );
  }

  /// Streams events of analysis [id]. Reconnects when the connection drops
  /// before `done`/`error`; the server replays all events, and the consumer
  /// state is idempotent, so duplicates are harmless. Always ends with
  /// [DoneEvent] or [ErrorEvent].
  Stream<AnalysisEvent> events(String id) async* {
    final uri = _uri('/v1/analyses/${Uri.encodeComponent(id)}/events');
    var failures = 0;
    var reconnects = 0;
    while (true) {
      Duration? wait;
      try {
        final req = http.Request('GET', uri)
          ..headers.addAll({..._headers, 'Accept': 'text/event-stream'});
        final resp = await _http.send(req);
        if (resp.statusCode == 404) {
          yield const ErrorEvent('not_found');
          return;
        }
        if (resp.statusCode == 429) {
          wait = _retryAfter(resp.headers) ?? reconnectDelay;
          await resp.stream.drain<void>();
        } else if (resp.statusCode != 200) {
          final body = await resp.stream.bytesToString();
          final err = _errorFrom(resp.statusCode, resp.headers, body);
          if (resp.statusCode < 500) {
            yield ErrorEvent(err.code, err.message);
            return;
          }
        } else {
          await for (final raw in parseSse(resp.stream)) {
            final ev = AnalysisEvent.fromSse(raw);
            if (ev == null) continue;
            failures = 0;
            yield ev;
            if (ev is DoneEvent || ev is ErrorEvent) return;
          }
        }
      } on Exception {
        // Dropped connection or DNS failure; fall through to reconnect.
      }
      failures++;
      reconnects++;
      if (failures > maxConsecutiveFailures || reconnects > maxReconnects) {
        yield const ErrorEvent('connection_lost');
        return;
      }
      await Future<void>.delayed(wait ?? reconnectDelay * failures);
    }
  }

  void close() => _http.close();

  static Map<String, dynamic>? _decodeMap(String s) {
    try {
      final v = jsonDecode(s);
      return v is Map ? v.cast<String, dynamic>() : null;
    } on FormatException {
      return null;
    }
  }

  static Duration? _retryAfter(Map<String, String> headers) {
    final v = headers['retry-after'];
    if (v == null) return null;
    final secs = int.tryParse(v.trim());
    if (secs != null) return Duration(seconds: secs < 0 ? 0 : secs);
    final date = DateTime.tryParse(v);
    if (date == null) return null;
    final d = date.difference(DateTime.now());
    return d.isNegative ? Duration.zero : d;
  }

  static ApiException _errorFrom(
    int status,
    Map<String, String> headers,
    String body,
  ) {
    final err = _decodeMap(body)?['error'];
    String? code;
    String? message;
    if (err is Map) {
      code = err['code'] is String ? err['code'] as String : null;
      message = err['message'] is String ? err['message'] as String : null;
    }
    code ??= switch (status) {
      400 => 'bad_request',
      413 => 'too_large',
      422 => 'fetch_failed',
      429 => 'rate_limited',
      404 => 'not_found',
      _ => 'internal',
    };
    return ApiException(
      code,
      message: message,
      status: status,
      retryAfter: status == 429 ? _retryAfter(headers) : null,
    );
  }
}
