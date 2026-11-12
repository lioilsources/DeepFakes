import 'models.dart';

/// Immutable view state built by folding [AnalysisEvent]s. Applying the same
/// event twice yields the same state, which makes SSE replay after a
/// reconnect harmless.
class AnalysisState {
  const AnalysisState({
    this.status = 'connecting',
    this.document,
    this.results = const {},
    this.summary,
    this.error,
    this.done = false,
  });

  final String status;
  final AnalysisDocument? document;
  final Map<int, ParagraphResult> results;
  final AnalysisSummary? summary;
  final ErrorEvent? error;
  final bool done;

  bool get finished => done || error != null;

  int get totalParagraphs => document?.paragraphs.length ?? 0;

  AnalysisState apply(AnalysisEvent e) => switch (e) {
    StatusEvent(:final status) =>
      _rank(status) > _rank(this.status) ? _copy(status: status) : this,
    DocumentEvent(:final document) => _copy(document: document),
    ParagraphEvent(:final result) => _copy(
      results: {...results, result.p: result},
      status: _rank('analyzing') > _rank(status) ? 'analyzing' : null,
    ),
    SummaryEvent(:final summary) => _copy(summary: summary),
    ErrorEvent() => _copy(error: e),
    DoneEvent() => _copy(done: true, status: 'done'),
  };

  /// Overall score: the server summary, or a provisional mean of analysed
  /// paragraphs while the summary has not arrived.
  int? get score {
    if (summary != null) return summary!.score;
    if (results.isEmpty) return null;
    final sum = results.values.fold<int>(0, (a, r) => a + r.score);
    return (sum / results.length).round();
  }

  bool get scoreIsProvisional => summary == null && results.isNotEmpty;

  Map<String, double> get emotions {
    if (summary != null && summary!.emotions.isNotEmpty) {
      return summary!.emotions;
    }
    if (results.isEmpty) return const {};
    final acc = <String, double>{};
    for (final r in results.values) {
      r.emotions.forEach((k, v) => acc[k] = (acc[k] ?? 0) + v);
    }
    return acc.map((k, v) => MapEntry(k, v / results.length));
  }

  Map<String, int> get techniqueCounts {
    if (summary != null) return summary!.techniques;
    final acc = <String, int>{};
    for (final r in results.values) {
      for (final t in r.techniques) {
        acc[t.technique] = (acc[t.technique] ?? 0) + 1;
      }
    }
    return acc;
  }

  static const _order = [
    'connecting',
    'queued',
    'fetching',
    'analyzing',
    'done',
  ];

  // Replayed status events must not move the visible status backwards.
  static int _rank(String s) {
    final i = _order.indexOf(s);
    return i < 0 ? 0 : i;
  }

  AnalysisState _copy({
    String? status,
    AnalysisDocument? document,
    Map<int, ParagraphResult>? results,
    AnalysisSummary? summary,
    ErrorEvent? error,
    bool? done,
  }) => AnalysisState(
    status: status ?? this.status,
    document: document ?? this.document,
    results: results ?? this.results,
    summary: summary ?? this.summary,
    error: error ?? this.error,
    done: done ?? this.done,
  );
}
