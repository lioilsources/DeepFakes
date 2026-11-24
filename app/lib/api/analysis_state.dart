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
    this.claims = const {},
    this.verdicts = const {},
    this.claimsSummary,
    this.error,
    this.done = false,
  });

  /// Folds [events] into a fresh state, e.g. [AnalysisResult.toEvents].
  factory AnalysisState.fromEvents(Iterable<AnalysisEvent> events) =>
      events.fold(const AnalysisState(), (s, e) => s.apply(e));

  final String status;
  final AnalysisDocument? document;
  final Map<int, ParagraphResult> results;
  final AnalysisSummary? summary;

  /// Claims by id, in arrival order.
  final Map<String, Claim> claims;

  /// Verdicts by claim id. Kept apart from [claims] because a verdict may
  /// arrive before its claim (reconnect, replay) and a replayed claim must not
  /// erase a verdict that already arrived.
  final Map<String, Verdict> verdicts;
  final ClaimsSummary? claimsSummary;
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
    ClaimEvent(:final claim) => _copy(
      claims: {...claims, claim.id: claim},
      verdicts: claim.verdict == null
          ? null
          : {...verdicts, claim.id: claim.verdict!},
    ),
    VerdictEvent(:final verdict) => _copy(
      verdicts: {...verdicts, verdict.claimId: verdict},
    ),
    ClaimsSummaryEvent(:final summary) => _copy(claimsSummary: summary),
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

  Verdict? verdictOf(String claimId) => verdicts[claimId];

  /// Claims with a verdict other than `not_checked` (or still checking), in
  /// reading order.
  List<Claim> get checkedClaims =>
      _sorted(claims.values.where((c) => !_notChecked(c)));

  /// Opinions, predictions and claims over the limit, in reading order.
  List<Claim> get notCheckedClaims => _sorted(claims.values.where(_notChecked));

  /// Count per verdict label: the server summary, or computed from verdicts
  /// that arrived so far.
  Map<String, int> get claimLabelCounts {
    final cs = claimsSummary;
    if (cs != null && cs.byLabel.isNotEmpty) return cs.byLabel;
    final acc = <String, int>{};
    for (final c in claims.values) {
      final v = verdicts[c.id];
      if (v != null) acc[v.label] = (acc[v.label] ?? 0) + 1;
    }
    return acc;
  }

  /// Number of claims that were (or are being) checked.
  int get claimsChecked => claimsSummary?.checked ?? checkedClaims.length;

  bool _notChecked(Claim c) => verdicts[c.id]?.label == 'not_checked';

  static List<Claim> _sorted(Iterable<Claim> it) => it.toList()
    ..sort((a, b) {
      final byP = a.p.compareTo(b.p);
      return byP != 0 ? byP : a.start.compareTo(b.start);
    });

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
    Map<String, Claim>? claims,
    Map<String, Verdict>? verdicts,
    ClaimsSummary? claimsSummary,
    ErrorEvent? error,
    bool? done,
  }) => AnalysisState(
    status: status ?? this.status,
    document: document ?? this.document,
    results: results ?? this.results,
    summary: summary ?? this.summary,
    claims: claims ?? this.claims,
    verdicts: verdicts ?? this.verdicts,
    claimsSummary: claimsSummary ?? this.claimsSummary,
    error: error ?? this.error,
    done: done ?? this.done,
  );
}
