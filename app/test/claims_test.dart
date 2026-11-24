import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pravdomer/api/analysis_state.dart';
import 'package:pravdomer/api/models.dart';
import 'package:pravdomer/api/sse.dart';
import 'package:pravdomer/widgets/highlight_spans.dart';

import 'fixtures.dart';

Map<String, dynamic> j(String s) => jsonDecode(s) as Map<String, dynamic>;

ClaimEvent claim(String id, {int p = 1, String kind = 'fact', int start = 0}) =>
    ClaimEvent(
      Claim.fromJson({
        'id': id,
        'p': p,
        'kind': kind,
        'start': start,
        'claim': 'Tvrzení $id',
      }),
    );

VerdictEvent verdict(String id, String label, {String? reason}) => VerdictEvent(
  Verdict.fromJson({'claim_id': id, 'label': label, 'reason': ?reason}),
);

void main() {
  group('models', () {
    test('claim', () {
      final c = Claim.fromJson(j(claimJson));
      expect(c.id, 'c1');
      expect(c.p, 1);
      expect((c.start, c.end), (6, 24));
      expect(c.kind, 'fact');
      expect(c.checkworthy, 0.9);
      expect(c.entities, ['vláda']);
      expect(c.verdict, isNull);
    });

    test('verdict with evidence and fact-check', () {
      final v = Verdict.fromJson(j(verdictJson));
      expect(v.claimId, 'c1');
      expect(v.label, 'supported');
      expect(v.confidence, 0.62);
      expect(v.showsConfidence, isTrue);
      expect(v.independentSources, 2);
      expect(v.sourcesConsidered, 4);
      final e = v.evidence.single;
      expect(e.site, 'mfcr.gov.cz');
      expect(e.sourceType, 'primary');
      expect(e.stance, 'supports');
      expect(e.quote, 'schodek ve výši 230 miliard Kč');
      expect(e.cluster, 1);
      expect(e.publishedAt, DateTime.utc(2026, 11, 12, 8));
      expect(e.factcheck?.publisher, 'Demagog.cz');
      expect(e.factcheck?.rating, 'Pravda');
    });

    test('unknown enum values are kept raw, confidence hidden', () {
      final v = Verdict.fromJson({
        'claim_id': 'c9',
        'label': 'half_true',
        'reason': 'cosmic_rays',
        'confidence': 0.5,
        'evidence': [
          {'source_type': 'blog', 'stance': 'neutral', 'factcheck': {}},
          'garbage',
        ],
      });
      expect(v.label, 'half_true');
      expect(v.reason, 'cosmic_rays');
      expect(v.showsConfidence, isFalse);
      final e = v.evidence.single;
      expect(e.sourceType, 'blog');
      expect(e.stance, 'neutral');
      expect(e.factcheck, isNull);
      expect(e.url, isNull);
    });

    test('unverifiable without evidence; empty verdict defaults', () {
      final v = Verdict.fromJson({
        'claim_id': 'c2',
        'label': 'unverifiable',
        'reason': 'no_sources',
        'confidence': 0.1,
      });
      expect(v.evidence, isEmpty);
      expect(v.explanation, isNull);
      expect(v.showsConfidence, isFalse);
      expect(Verdict.fromJson({}).label, 'unverifiable');
    });

    test('claims summary with error', () {
      final s = ClaimsSummary.fromJson(j(claimsSummaryJson));
      expect(s.claimsFound, 9);
      expect(s.checked, 6);
      expect(s.byLabel['supported'], 3);
      expect(s.providers, hasLength(3));
      expect(s.error, isNull);
      expect(
        ClaimsSummary.fromJson({'error': 'llm_unavailable'}).error,
        'llm_unavailable',
      );
    });

    test('purged GET result parses and folds into state', () {
      final r = AnalysisResult.fromJson(j(purgedResultJson));
      expect(r.claims, hasLength(2));
      final c1 = r.claims.first;
      expect(c1.quote, isEmpty);
      expect(c1.claim, isEmpty);
      expect(c1.verdict?.claimId, 'c1', reason: 'nested verdict gets claim id');
      expect(c1.verdict?.evidence.single.quote, isEmpty);

      final s = AnalysisState.fromEvents(r.toEvents());
      expect(s.done, isTrue);
      expect(s.claims.keys, ['c1', 'c2']);
      expect(s.verdictOf('c1')?.label, 'refuted');
      expect(s.verdictOf('c2'), isNull);
      expect(s.claimsSummary?.checked, 1);
      // Purged quote: offsets still place the mark only if the text has them.
      expect(claimRange('', c1), isNull);
    });

    test('SSE mapping of claim events', () {
      expect(
        AnalysisEvent.fromSse(SseEvent(event: 'claim', data: claimJson)),
        isA<ClaimEvent>(),
      );
      expect(
        AnalysisEvent.fromSse(SseEvent(event: 'verdict', data: verdictJson)),
        isA<VerdictEvent>(),
      );
      expect(
        AnalysisEvent.fromSse(
          SseEvent(event: 'claims_summary', data: claimsSummaryJson),
        ),
        isA<ClaimsSummaryEvent>(),
      );
      expect(
        AnalysisEvent.fromSse(const SseEvent(event: 'claim', data: '{}')),
        isNull,
        reason: 'claim without id',
      );
      expect(
        AnalysisEvent.fromSse(const SseEvent(event: 'verdict', data: '{')),
        isNull,
      );
    });

    test('claim range uses offsets, falls back to search', () {
      const text = 'První odstavec je klidný.';
      final c = Claim.fromJson(j(claimJson));
      expect(claimRange(text, c), (start: 6, end: 24));
      final shifted = Claim.fromJson({...j(claimJson), 'start': 0, 'end': 3});
      expect(claimRange(text, shifted), (start: 6, end: 24));
      final missing = Claim.fromJson({...j(claimJson), 'quote': 'nic'});
      expect(claimRange(text, missing), isNull);
    });
  });

  group('state', () {
    test('verdict before its claim and out of order', () {
      var s = const AnalysisState();
      s = s.apply(verdict('c2', 'refuted'));
      expect(s.checkedClaims, isEmpty, reason: 'verdict alone is not a claim');
      s = s
          .apply(claim('c1', p: 2))
          .apply(claim('c2', p: 1))
          .apply(claim('c3', p: 1, kind: 'opinion', start: 5));
      expect(s.verdictOf('c2')?.label, 'refuted');
      expect(s.verdictOf('c1'), isNull, reason: 'c1 still checking');
      s = s
          .apply(verdict('c3', 'not_checked', reason: 'opinion'))
          .apply(verdict('c1', 'supported'));
      // Reading order (p, start), not arrival order.
      expect(s.checkedClaims.map((c) => c.id), ['c2', 'c1']);
      expect(s.notCheckedClaims.map((c) => c.id), ['c3']);
      expect(s.claimLabelCounts, {
        'refuted': 1,
        'supported': 1,
        'not_checked': 1,
      });
      expect(s.claimsChecked, 2);
    });

    test('replay after reconnect keeps verdicts and is idempotent', () {
      final events = <AnalysisEvent>[
        DocumentEvent(AnalysisDocument.fromJson(j(documentJson))),
        ClaimEvent(Claim.fromJson(j(claimJson))),
        claim('c2'),
        VerdictEvent(Verdict.fromJson(j(verdictJson))),
      ];
      var s = AnalysisState.fromEvents(events);
      // Replay: claim events again, without nested verdicts.
      for (final e in events) {
        s = s.apply(e);
      }
      expect(s.claims, hasLength(2));
      expect(s.verdictOf('c1')?.label, 'supported');
      s = s
          .apply(ClaimEvent(Claim.fromJson(j(claimJson))))
          .apply(verdict('c2', 'unverifiable', reason: 'no_sources'))
          .apply(
            ClaimsSummaryEvent(ClaimsSummary.fromJson(j(claimsSummaryJson))),
          )
          .apply(const DoneEvent());
      expect(s.verdictOf('c1')?.label, 'supported');
      expect(s.verdictOf('c2')?.reason, 'no_sources');
      // Server summary wins over locally computed counts.
      expect(s.claimsChecked, 6);
      expect(s.claimLabelCounts['supported'], 3);
    });
  });
}
