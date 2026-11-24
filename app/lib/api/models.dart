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

// ---- Claims (M2) ----------------------------------------------------------

/// Verdict labels for which a confidence estimate is meaningful.
const confidenceLabels = {
  'supported',
  'mostly_supported',
  'disputed',
  'refuted',
};

/// A claim extracted from the document. After the cache TTL the server purges
/// `quote`, `claim` and `entities`, so they may be empty.
class Claim {
  const Claim({
    required this.id,
    required this.p,
    this.quote = '',
    this.start = 0,
    this.end = 0,
    this.claim = '',
    this.kind = 'fact',
    this.checkworthy,
    this.entities = const [],
    this.verdict,
  });

  factory Claim.fromJson(Map<String, dynamic> j) {
    final id = _str(j['id']) ?? '';
    final v = j['verdict'];
    return Claim(
      id: id,
      p: _toIntOrNull(j['p']) ?? 0,
      quote: _str(j['quote']) ?? '',
      start: _toIntOrNull(j['start']) ?? 0,
      end: _toIntOrNull(j['end']) ?? 0,
      claim: _str(j['claim']) ?? '',
      kind: _str(j['kind']) ?? 'fact',
      checkworthy: j['checkworthy'] is num ? _toDouble(j['checkworthy']) : null,
      entities: _list(j['entities']).whereType<String>().toList(),
      verdict: v is Map
          ? Verdict.fromJson(v.cast<String, dynamic>(), claimId: id)
          : null,
    );
  }

  final String id;

  /// Paragraph number (from 1).
  final int p;
  final String quote;

  /// UTF-16 code unit offsets into paragraph [p].
  final int start;
  final int end;
  final String claim;

  /// `fact | opinion | prediction`; unknown values are kept raw.
  final String kind;
  final double? checkworthy;
  final List<String> entities;

  /// Only set when parsed from `GET /v1/analyses/{id}`.
  final Verdict? verdict;
}

/// Fact-check rating in the publisher's own wording.
class FactCheck {
  const FactCheck({this.publisher, this.rating});

  static FactCheck? fromJson(Object? v) {
    final j = _map(v);
    final f = FactCheck(
      publisher: _str(j['publisher']),
      rating: _str(j['rating']),
    );
    return f.publisher == null && f.rating == null ? null : f;
  }

  final String? publisher;
  final String? rating;
}

class Evidence {
  const Evidence({
    this.url,
    this.title,
    this.site,
    this.sourceType = 'unknown',
    this.stance = '',
    this.quote = '',
    this.confidence,
    this.weight,
    this.cluster,
    this.publishedAt,
    this.retrievedAt,
    this.factcheck,
  });

  factory Evidence.fromJson(Map<String, dynamic> j) {
    final published = _str(j['published_at']);
    final retrieved = _str(j['retrieved_at']);
    return Evidence(
      url: _str(j['url']),
      title: _str(j['title']),
      site: _str(j['site']),
      sourceType: _str(j['source_type']) ?? 'unknown',
      stance: _str(j['stance']) ?? '',
      quote: _str(j['quote']) ?? '',
      confidence: j['confidence'] is num ? _toDouble(j['confidence']) : null,
      weight: j['weight'] is num ? _toDouble(j['weight']) : null,
      cluster: _toIntOrNull(j['cluster']),
      publishedAt: published == null ? null : DateTime.tryParse(published),
      retrievedAt: retrieved == null ? null : DateTime.tryParse(retrieved),
      factcheck: FactCheck.fromJson(j['factcheck']),
    );
  }

  final String? url;
  final String? title;
  final String? site;

  /// `fact_checker | primary | encyclopedia | news | unknown`, or raw.
  final String sourceType;

  /// `supports | refutes`, or raw.
  final String stance;

  /// Verbatim quote from the source; empty after purge.
  final String quote;
  final double? confidence;
  final double? weight;
  final int? cluster;
  final DateTime? publishedAt;
  final DateTime? retrievedAt;
  final FactCheck? factcheck;
}

class Verdict {
  const Verdict({
    required this.claimId,
    required this.label,
    this.reason,
    this.confidence,
    this.explanation,
    this.support,
    this.refute,
    this.independentSources,
    this.sourcesConsidered,
    this.evidence = const [],
  });

  /// [claimId] is the fallback for verdicts nested in a claim.
  factory Verdict.fromJson(Map<String, dynamic> j, {String? claimId}) =>
      Verdict(
        claimId: _str(j['claim_id']) ?? claimId ?? '',
        label: _str(j['label']) ?? 'unverifiable',
        reason: _str(j['reason']),
        confidence: j['confidence'] is num
            ? _toDouble(j['confidence']).clamp(0.0, 1.0)
            : null,
        explanation: _str(j['explanation']),
        support: j['support'] is num ? _toDouble(j['support']) : null,
        refute: j['refute'] is num ? _toDouble(j['refute']) : null,
        independentSources: _toIntOrNull(j['independent_sources']),
        sourcesConsidered: _toIntOrNull(j['sources_considered']),
        evidence: _list(j['evidence'])
            .whereType<Map>()
            .map((e) => Evidence.fromJson(e.cast<String, dynamic>()))
            .toList(),
      );

  final String claimId;

  /// `supported | mostly_supported | disputed | refuted | unverifiable |
  /// not_checked`, or raw.
  final String label;
  final String? reason;

  /// Heuristic, not a calibrated probability.
  final double? confidence;

  /// Model summary of the cited passages.
  final String? explanation;
  final double? support;
  final double? refute;
  final int? independentSources;
  final int? sourcesConsidered;
  final List<Evidence> evidence;

  bool get showsConfidence =>
      confidence != null && confidenceLabels.contains(label);
}

class ClaimsSummary {
  const ClaimsSummary({
    this.claimsFound,
    this.checked,
    this.byLabel = const {},
    this.quotesDropped,
    this.evidenceQuotesDropped,
    this.searches,
    this.searchErrors,
    this.pagesFetched,
    this.providers = const [],
    this.model,
    this.method,
    this.latencyMs,
    this.error,
  });

  factory ClaimsSummary.fromJson(Map<String, dynamic> j) {
    final byLabel = <String, int>{};
    _map(j['by_label']).forEach((k, v) {
      if (v is num && v > 0) byLabel[k] = v.round();
    });
    return ClaimsSummary(
      claimsFound: _toIntOrNull(j['claims_found']),
      checked: _toIntOrNull(j['checked']),
      byLabel: byLabel,
      quotesDropped: _toIntOrNull(j['quotes_dropped']),
      evidenceQuotesDropped: _toIntOrNull(j['evidence_quotes_dropped']),
      searches: _toIntOrNull(j['searches']),
      searchErrors: _toIntOrNull(j['search_errors']),
      pagesFetched: _toIntOrNull(j['pages_fetched']),
      providers: _list(j['providers']).whereType<String>().toList(),
      model: _str(j['model']),
      method: _str(j['method']),
      latencyMs: _toIntOrNull(j['latency_ms']),
      error: _str(j['error']),
    );
  }

  final int? claimsFound;
  final int? checked;
  final Map<String, int> byLabel;
  final int? quotesDropped;
  final int? evidenceQuotesDropped;
  final int? searches;
  final int? searchErrors;
  final int? pagesFetched;
  final List<String> providers;
  final String? model;
  final String? method;
  final int? latencyMs;

  /// `llm_unavailable | internal`: claim checking failed; temperature is
  /// unaffected.
  final String? error;
}

/// Response of `GET /v1/analyses/{id}`. Converted to the same events as the
/// SSE stream so one reducer handles both.
class AnalysisResult {
  const AnalysisResult({
    required this.id,
    required this.status,
    this.document,
    this.paragraphs = const [],
    this.summary,
    this.claims = const [],
    this.claimsSummary,
    this.error,
  });

  factory AnalysisResult.fromJson(Map<String, dynamic> j) {
    final doc = j['document'];
    final sum = j['summary'];
    final cs = j['claims_summary'];
    final err = j['error'];
    return AnalysisResult(
      id: _str(j['id']) ?? '',
      status: _str(j['status']) ?? 'queued',
      document: doc is Map
          ? AnalysisDocument.fromJson(doc.cast<String, dynamic>())
          : null,
      paragraphs: _list(j['paragraphs'])
          .whereType<Map>()
          .map((e) => ParagraphResult.fromJson(e.cast<String, dynamic>()))
          .where((r) => r.p > 0)
          .toList(),
      summary: sum is Map
          ? AnalysisSummary.fromJson(sum.cast<String, dynamic>())
          : null,
      claims: _list(j['claims'])
          .whereType<Map>()
          .map((e) => Claim.fromJson(e.cast<String, dynamic>()))
          .where((c) => c.id.isNotEmpty)
          .toList(),
      claimsSummary: cs is Map
          ? ClaimsSummary.fromJson(cs.cast<String, dynamic>())
          : null,
      error: err is Map
          ? ErrorEvent(_str(err['code']) ?? 'internal', _str(err['message']))
          : err is String && err.isNotEmpty
          ? ErrorEvent(err)
          : null,
    );
  }

  final String id;
  final String status;
  final AnalysisDocument? document;
  final List<ParagraphResult> paragraphs;
  final AnalysisSummary? summary;
  final List<Claim> claims;
  final ClaimsSummary? claimsSummary;
  final ErrorEvent? error;

  List<AnalysisEvent> toEvents() => [
    if (status == 'running') const StatusEvent('analyzing'),
    if (status == 'queued') const StatusEvent('queued'),
    if (document != null) DocumentEvent(document!),
    for (final r in paragraphs) ParagraphEvent(r),
    if (summary != null) SummaryEvent(summary!),
    for (final c in claims) ClaimEvent(c),
    if (claimsSummary != null) ClaimsSummaryEvent(claimsSummary!),
    ?error,
    if (status == 'done') const DoneEvent(),
    if (status == 'failed' && error == null) const ErrorEvent('internal'),
  ];
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
      case 'claim':
        if (j == null) return null;
        final c = Claim.fromJson(j);
        return c.id.isEmpty ? null : ClaimEvent(c);
      case 'verdict':
        if (j == null) return null;
        final v = Verdict.fromJson(j);
        return v.claimId.isEmpty ? null : VerdictEvent(v);
      case 'claims_summary':
        return j == null ? null : ClaimsSummaryEvent(ClaimsSummary.fromJson(j));
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

class ClaimEvent extends AnalysisEvent {
  const ClaimEvent(this.claim);
  final Claim claim;
}

class VerdictEvent extends AnalysisEvent {
  const VerdictEvent(this.verdict);
  final Verdict verdict;
}

class ClaimsSummaryEvent extends AnalysisEvent {
  const ClaimsSummaryEvent(this.summary);
  final ClaimsSummary summary;
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
