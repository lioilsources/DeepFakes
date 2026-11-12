import 'package:flutter_test/flutter_test.dart';
import 'package:pravdomer/api/models.dart';
import 'package:pravdomer/widgets/highlight_spans.dart';

TechniqueHit hit(String text, String quote, String technique, {int from = 0}) {
  final start = text.indexOf(quote, from);
  assert(start >= 0);
  return TechniqueHit(
    technique: technique,
    quote: quote,
    start: start,
    end: start + quote.length,
  );
}

String joined(String text, List<HighlightSegment> segs) =>
    segs.map((s) => s.textOf(text)).join();

void main() {
  test('no hits gives a single plain segment', () {
    final segs = buildHighlightSegments('Klidný text.', const []);
    expect(segs, hasLength(1));
    expect(segs.single.highlighted, isFalse);
  });

  test('empty text gives no segments', () {
    expect(buildHighlightSegments('', const []), isEmpty);
  });

  test('overlapping quotes split into exact runs', () {
    const text = 'Tihle zrádci zničí naši zemi navždy.';
    final a = hit(text, 'zrádci zničí', 'name_calling');
    final b = hit(text, 'zničí naši zemi', 'fear_appeal');
    final segs = buildHighlightSegments(text, [a, b]);
    expect(joined(text, segs), text);
    expect(
      segs.map(
        (s) => '${s.textOf(text)}|${s.hits.map((h) => h.technique).join(',')}',
      ),
      [
        'Tihle |',
        'zrádci |name_calling',
        'zničí|name_calling,fear_appeal',
        ' naši zemi|fear_appeal',
        ' navždy.|',
      ],
    );
  });

  test('nested quote and identical ranges', () {
    const text = 'Oni chtějí zničit všechno, co máme.';
    final outer = hit(text, 'chtějí zničit všechno', 'exaggeration');
    final inner = hit(text, 'zničit', 'fear_appeal');
    final dup = hit(text, 'zničit', 'loaded_language');
    final segs = buildHighlightSegments(text, [outer, inner, dup]);
    expect(joined(text, segs), text);
    final mid = segs.firstWhere((s) => s.textOf(text) == 'zničit');
    expect(mid.hits.map((h) => h.technique), [
      'exaggeration',
      'fear_appeal',
      'loaded_language',
    ]);
  });

  test('emoji and diacritics use UTF-16 offsets', () {
    const text = 'Šílenci 🤬🤬 zase řádí — příšerná katastrofa!';
    final q = hit(text, 'příšerná katastrofa', 'exaggeration');
    final e = hit(text, '🤬🤬 zase', 'loaded_language');
    // Emoji outside the BMP take two code units each.
    expect('🤬'.length, 2);
    expect(e.end - e.start, 9);
    final segs = buildHighlightSegments(text, [q, e]);
    expect(joined(text, segs), text);
    final texts = segs.where((s) => s.highlighted).map((s) => s.textOf(text));
    expect(texts, ['🤬🤬 zase', 'příšerná katastrofa']);
  });

  test('out-of-range and surrogate-splitting offsets are repaired', () {
    const text = 'Ahoj 🤬 světe';
    final emojiStart = text.indexOf('🤬');
    final segs = buildHighlightSegments(text, const [
      TechniqueHit(technique: 'x', quote: '', start: 8, end: 999),
      TechniqueHit(technique: 'y', quote: '', start: 5, end: 3),
      // Ends between the two halves of the emoji.
      TechniqueHit(technique: 'z', quote: '', start: 0, end: 6),
    ]);
    expect(joined(text, segs), text);
    expect(segs.every((s) => s.end <= text.length), isTrue);
    final z = segs.firstWhere((s) => s.hits.any((h) => h.technique == 'z'));
    expect(z.end, emojiStart + 2);
    expect(segs.any((s) => s.hits.any((h) => h.technique == 'y')), isFalse);
  });
}
