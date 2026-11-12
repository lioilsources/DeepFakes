// Data models for the Pravdoměr API (docs/API.md). Parsing is tolerant:
// missing or mistyped optional fields fall back to empty values instead of
// throwing.

import 'dart:convert';

import 'sse.dart';

double _toDouble(Object? v) => v is num ? v.toDouble() : 0.0;
int? _toIntOrNull(Object? v) => v is num ? v.round() : null;
String? _str(Object? v) => v is String && v.isNotEmpty ? v : null;
Map<String, dynamic> _map(Object? v) =>
    v is Map ? v.cast<String, dynamic>() : const <String, dynamic>{};
List<dynamic> _list(Object? v) => v is List ? v : const <dynamic>[];

Map<String, double> _emotions(Object? v) {
  final out = <String, double>{};
  _map(v).forEach((k, val) {
    if (val is num) out[k] = val.toDouble().clamp(0.0, 1.0);
  });
  return out;
}

class ParagraphText {
  const ParagraphText({required this.p, required this.text});

  factory ParagraphText.fromJson(Map<String, dynamic> j) =>
      ParagraphText(p: _toIntOrNull(j['p']) ?? 0, text: _str(j['text']) ?? '');

  final int p;
  final String text;
}

class AnalysisDocument {
  const AnalysisDocument({
    this.url,
    this.title,
    this.author,
    this.publishedAt,
    this.site,
    this.language,
    this.paragraphs = const [],
  });

  factory AnalysisDocument.fromJson(Map<String, dynamic> j) {
    final paragraphs =
        _list(j['paragraphs'])
            .whereType<Map>()
            .map((e) => ParagraphText.fromJson(e.cast<String, dynamic>()))
            .where((p) => p.p > 0)
            .toList()
          ..sort((a, b) => a.p.compareTo(b.p));
    final published = _str(j['published_at']);
    return AnalysisDocument(
      url: _str(j['url']),
      title: _str(j['title']),
      author: _str(j['author']),
      publishedAt: published == null ? null : DateTime.tryParse(published),
      site: _str(j['site']),
      language: _str(j['language']),
      paragraphs: paragraphs,
    );
  }

  final String? url;
  final String? title;
  final String? author;
  final DateTime? publishedAt;
  final String? site;
  final String? language;
  final List<ParagraphText> paragraphs;
}

class TechniqueHit {
  const TechniqueHit({
    required this.technique,
    required this.quote,
    required this.start,
    required this.end,
    this.confidence,
  });

  factory TechniqueHit.fromJson(Map<String, dynamic> j) => TechniqueHit(
    technique: _str(j['technique']) ?? 'unknown',
    quote: _str(j['quote']) ?? '',
    start: _toIntOrNull(j['start']) ?? 0,
    end: _toIntOrNull(j['end']) ?? 0,
    confidence: j['confidence'] is num ? _toDouble(j['confidence']) : null,
  );

  final String technique;
  final String quote;

  /// UTF-16 code unit offsets into the paragraph text.
  final int start;
  final int end;
  final double? confidence;
}

class ParagraphResult {
  const ParagraphResult({
    required this.p,
    required this.score,
    this.emotions = const {},
    this.loadedLanguage,
    this.techniques = const [],
  });

  factory ParagraphResult.fromJson(Map<String, dynamic> j) => ParagraphResult(
    p: _toIntOrNull(j['p']) ?? 0,
    score: (_toIntOrNull(j['score']) ?? 0).clamp(0, 100),
    emotions: _emotions(j['emotions']),
    loadedLanguage: j['loaded_language'] is num
        ? _toDouble(j['loaded_language'])
        : null,
    techniques: _list(j['techniques'])
        .whereType<Map>()
        .map((e) => TechniqueHit.fromJson(e.cast<String, dynamic>()))
        .toList(),
  );

  final int p;
  final int score;
  final Map<String, double> emotions;
  final double? loadedLanguage;
  final List<TechniqueHit> techniques;
}

class AnalysisSummary {
  const AnalysisSummary({
    required this.score,
    this.emotions = const {},
    this.techniques = const {},
    this.headlineClickbait,
    this.headlineMatchesBody,
    this.paragraphsAnalyzed,
    this.paragraphsFailed,
    this.quotesDropped,
    this.model,
    this.method,
    this.latencyMs,
  });

  factory AnalysisSummary.fromJson(Map<String, dynamic> j) {
    final techniques = <String, int>{};
    _map(j['techniques']).forEach((k, v) {
      if (v is num && v > 0) techniques[k] = v.round();
    });
    return AnalysisSummary(
      score: (_toIntOrNull(j['score']) ?? 0).clamp(0, 100),
      emotions: _emotions(j['emotions']),
      techniques: techniques,
      headlineClickbait: j['headline_clickbait'] is num
          ? _toDouble(j['headline_clickbait'])
          : null,
      headlineMatchesBody: j['headline_matches_body'] is bool
          ? j['headline_matches_body'] as bool
          : null,
      paragraphsAnalyzed: _toIntOrNull(j['paragraphs_analyzed']),
      paragraphsFailed: _toIntOrNull(j['paragraphs_failed']),
      quotesDropped: _toIntOrNull(j['quotes_dropped']),
      model: _str(j['model']),
      method: _str(j['method']),
      latencyMs: _toIntOrNull(j['latency_ms']),
    );
  }

  final int score;
  final Map<String, double> emotions;
  final Map<String, int> techniques;
  final double? headlineClickbait;
  final bool? headlineMatchesBody;
  final int? paragraphsAnalyzed;
  final int? paragraphsFailed;
  final int? quotesDropped;
  final String? model;
  final String? method;
  final int? latencyMs;
}

/// Response of `POST /v1/analyses`.
class StartResponse {
  const StartResponse({required this.id, required this.status, this.events});

  factory StartResponse.fromJson(Map<String, dynamic> j) => StartResponse(
    id: _str(j['id']) ?? '',
    status: _str(j['status']) ?? 'queued',
    events: _str(j['events']),
  );

  final String id;
  final String status;
  final String? events;
}

// ---- SSE events -----------------------------------------------------------

Map<String, dynamic>? _decode(String data) {
  try {
    final v = jsonDecode(data);
    return v is Map ? v.cast<String, dynamic>() : null;
  } on FormatException {
    return null;
  }
}

sealed class AnalysisEvent {
  const AnalysisEvent();

  /// Maps a raw SSE event to a typed one; returns null for unknown types or
  /// unparsable data so that new server events do not break old apps.
  static AnalysisEvent? fromSse(SseEvent e) {
    final j = _decode(e.data);
    switch (e.event) {
      case 'status':
        return StatusEvent(_str(j?['status']) ?? 'analyzing');
      case 'document':
        return j == null ? null : DocumentEvent(AnalysisDocument.fromJson(j));
      case 'paragraph':
        if (j == null) return null;
        final r = ParagraphResult.fromJson(j);
        return r.p > 0 ? ParagraphEvent(r) : null;
      case 'summary':
        return j == null ? null : SummaryEvent(AnalysisSummary.fromJson(j));
      case 'error':
        return ErrorEvent(_str(j?['code']) ?? 'internal', _str(j?['message']));
      case 'done':
        return const DoneEvent();
      default:
        return null;
    }
  }
}

class StatusEvent extends AnalysisEvent {
  const StatusEvent(this.status);
  final String status;
}

class DocumentEvent extends AnalysisEvent {
  const DocumentEvent(this.document);
  final AnalysisDocument document;
}

class ParagraphEvent extends AnalysisEvent {
  const ParagraphEvent(this.result);
  final ParagraphResult result;
}

class SummaryEvent extends AnalysisEvent {
  const SummaryEvent(this.summary);
  final AnalysisSummary summary;
}

/// Terminal error, either sent by the server or synthesised by the client
/// (`network`, `not_found`, `connection_lost`).
class ErrorEvent extends AnalysisEvent {
  const ErrorEvent(this.code, [this.message]);
  final String code;
  final String? message;
}

class DoneEvent extends AnalysisEvent {
  const DoneEvent();
}
