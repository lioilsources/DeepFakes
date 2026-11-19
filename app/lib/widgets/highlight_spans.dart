import '../api/models.dart';

/// A run of paragraph text covered by the same set of techniques.
class HighlightSegment {
  const HighlightSegment(this.start, this.end, this.hits);

  final int start;
  final int end;

  /// Techniques whose quote covers this run; empty for plain text.
  final List<TechniqueHit> hits;

  bool get highlighted => hits.isNotEmpty;

  String textOf(String paragraph) => paragraph.substring(start, end);
}

bool _isHigh(int u) => u >= 0xD800 && u <= 0xDBFF;
bool _isLow(int u) => u >= 0xDC00 && u <= 0xDFFF;

/// Moves [i] forward if it would split a surrogate pair.
int _snap(String text, int i) {
  if (i > 0 &&
      i < text.length &&
      _isHigh(text.codeUnitAt(i - 1)) &&
      _isLow(text.codeUnitAt(i))) {
    return i + 1;
  }
  return i;
}

/// Splits [text] into consecutive segments at every quote boundary, so that
/// overlapping or nested quotes are represented exactly. Offsets are UTF-16
/// code units (the API contract), i.e. directly Dart string indices. Invalid
/// ranges are clamped or dropped; the result always covers the whole text.
List<HighlightSegment> buildHighlightSegments(
  String text,
  List<TechniqueHit> hits,
) {
  final len = text.length;
  final valid = <({int s, int e, TechniqueHit hit})>[];
  for (final h in hits) {
    final s = _snap(text, h.start.clamp(0, len));
    final e = _snap(text, h.end.clamp(0, len));
    if (e > s) valid.add((s: s, e: e, hit: h));
  }
  if (len == 0) return const [];
  if (valid.isEmpty) return [HighlightSegment(0, len, const [])];

  final cuts = <int>{0, len};
  for (final v in valid) {
    cuts
      ..add(v.s)
      ..add(v.e);
  }
  final points = cuts.toList()..sort();

  final out = <HighlightSegment>[];
  for (var i = 0; i < points.length - 1; i++) {
    final a = points[i];
    final b = points[i + 1];
    final covering = [
      for (final v in valid)
        if (v.s <= a && v.e >= b) v.hit,
    ];
    if (out.isNotEmpty && _sameHits(out.last.hits, covering)) {
      final last = out.removeLast();
      out.add(HighlightSegment(last.start, b, last.hits));
    } else {
      out.add(HighlightSegment(a, b, covering));
    }
  }
  return out;
}

bool _sameHits(List<TechniqueHit> a, List<TechniqueHit> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (!identical(a[i], b[i])) return false;
  }
  return true;
}

/// Range of a claim quote in [text], or null when it cannot be placed. Uses
/// the server offsets when they match the quote (always, per contract), falls
/// back to searching for the quote, and to the bare offsets when the quote
/// was purged.
({int start, int end})? claimRange(String text, Claim c) {
  final len = text.length;
  if (len == 0) return null;
  final s = _snap(text, c.start.clamp(0, len));
  final e = _snap(text, c.end.clamp(0, len));
  if (c.quote.isEmpty) return e > s ? (start: s, end: e) : null;
  if (e > s && text.substring(s, e) == c.quote) return (start: s, end: e);
  final i = text.indexOf(c.quote);
  return i < 0 ? null : (start: i, end: i + c.quote.length);
}

/// Splits [segments] additionally at [start] and [end], so that a second
/// highlight layer (the selected claim) can be styled per segment.
List<HighlightSegment> splitSegments(
  List<HighlightSegment> segments,
  int start,
  int end,
) {
  final out = <HighlightSegment>[];
  for (final seg in segments) {
    final cuts = <int>{seg.start, seg.end};
    if (start > seg.start && start < seg.end) cuts.add(start);
    if (end > seg.start && end < seg.end) cuts.add(end);
    final points = cuts.toList()..sort();
    for (var i = 0; i < points.length - 1; i++) {
      out.add(HighlightSegment(points[i], points[i + 1], seg.hits));
    }
  }
  return out;
}
