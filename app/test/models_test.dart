import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pravdomer/api/analysis_state.dart';
import 'package:pravdomer/api/models.dart';
import 'package:pravdomer/api/sse.dart';

import 'fixtures.dart';

Map<String, dynamic> j(String s) => jsonDecode(s) as Map<String, dynamic>;

void main() {
  test('document with all fields', () {
    final d = AnalysisDocument.fromJson(j(documentJson));
    expect(d.title, 'Titulek článku');
    expect(d.author, 'Jana Nováková');
    expect(d.publishedAt, DateTime.utc(2026, 11, 12, 8));
    expect(d.site, 'example.com');
    expect(d.language, 'cs');
    expect(d.paragraphs.map((p) => p.p), [1, 2]);
  });

  test('document without optional fields', () {
    final d = AnalysisDocument.fromJson(j(documentMinimalJson));
    expect(d.url, isNull);
    expect(d.author, isNull);
    expect(d.publishedAt, isNull);
    expect(d.site, isNull, reason: 'empty string treated as missing');
    expect(d.paragraphs.single.text, 'Jen text.');
  });

  test('paragraph result', () {
    final r = ParagraphResult.fromJson(j(paragraphJson));
    expect(r.p, 3);
    expect(r.score, 62);
    expect(r.emotions['anger'], 0.7);
    expect(r.emotions, hasLength(7));
    expect(r.loadedLanguage, 0.6);
    final t = r.techniques.single;
    expect(t.technique, 'name_calling');
    expect((t.start, t.end), (6, 12));
    expect(t.confidence, 0.8);
  });

  test('paragraph tolerates missing and mistyped fields', () {
    final r = ParagraphResult.fromJson({
      'p': 2,
      'score': 140.4,
      'emotions': 'x',
      'techniques': [1, {}],
    });
    expect(r.score, 100);
    expect(r.emotions, isEmpty);
    expect(r.loadedLanguage, isNull);
    expect(r.techniques.single.technique, 'unknown');
  });

  test('summary', () {
    final s = AnalysisSummary.fromJson(j(summaryJson));
    expect(s.score, 48);
    expect(s.techniques, {'name_calling': 3, 'fear_appeal': 1});
    expect(s.headlineClickbait, 0.4);
    expect(s.headlineMatchesBody, isTrue);
    expect(s.paragraphsAnalyzed, 12);
    expect(s.quotesDropped, 1);
    expect(s.model, 'deepfake-llm');
    expect(s.latencyMs, 18400);
  });

  test('summary with only a score', () {
    final s = AnalysisSummary.fromJson({'score': 10});
    expect(s.techniques, isEmpty);
    expect(s.headlineMatchesBody, isNull);
  });

  test('start response', () {
    final s = StartResponse.fromJson(j(startJson));
    expect(s.id, '01JCABC');
    expect(s.events, '/v1/analyses/01JCABC/events');
  });

  test('SSE mapping, unknown event and bad JSON are skipped', () {
    expect(
      AnalysisEvent.fromSse(
        const SseEvent(event: 'status', data: '{"status":"fetching"}'),
      ),
      isA<StatusEvent>().having((e) => e.status, 'status', 'fetching'),
    );
    expect(
      AnalysisEvent.fromSse(const SseEvent(event: 'done', data: '{}')),
      isA<DoneEvent>(),
    );
    expect(
      AnalysisEvent.fromSse(
        const SseEvent(
          event: 'error',
          data: '{"code":"llm_unavailable","message":"x"}',
        ),
      ),
      isA<ErrorEvent>().having((e) => e.code, 'code', 'llm_unavailable'),
    );
    expect(
      AnalysisEvent.fromSse(const SseEvent(event: 'future', data: '{}')),
      isNull,
    );
    expect(
      AnalysisEvent.fromSse(const SseEvent(event: 'paragraph', data: '{')),
      isNull,
    );
  });

  test('state is idempotent under replay and status never regresses', () {
    final events = [
      const StatusEvent('fetching'),
      DocumentEvent(AnalysisDocument.fromJson(j(documentJson))),
      const StatusEvent('analyzing'),
      ParagraphEvent(
        ParagraphResult.fromJson({
          'p': 2,
          'score': 80,
          'emotions': {'anger': 0.8},
        }),
      ),
    ];
    var s = const AnalysisState();
    for (final e in [...events, ...events]) {
      s = s.apply(e);
    }
    expect(s.status, 'analyzing');
    expect(s.results.keys, [2]);
    expect(s.score, 80);
    expect(s.scoreIsProvisional, isTrue);
    s = s.apply(SummaryEvent(AnalysisSummary.fromJson(j(summaryJson))));
    expect(s.score, 48);
    expect(s.scoreIsProvisional, isFalse);
    expect(s.techniqueCounts['name_calling'], 3);
  });
}
