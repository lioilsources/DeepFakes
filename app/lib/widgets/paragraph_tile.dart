import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../api/models.dart';
import '../l10n/app_localizations.dart';
import 'highlight_spans.dart';
import 'shimmer.dart';
import 'technique_sheet.dart';
import 'temperature.dart';

/// One paragraph of the document: text with highlighted technique quotes
/// once its result arrived, a shimmer overlay before that.
class ParagraphTile extends StatelessWidget {
  const ParagraphTile({
    super.key,
    required this.paragraph,
    this.result,
    this.finished = false,
  });

  final ParagraphText paragraph;
  final ParagraphResult? result;

  /// The stream ended; a missing result means the paragraph failed, so stop
  /// shimmering and show the plain text.
  final bool finished;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final r = result;
    return Card(
      key: Key('paragraph-${paragraph.p}'),
      margin: const EdgeInsets.symmetric(vertical: 6),
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('§ ${paragraph.p}', style: theme.textTheme.labelMedium),
                const Spacer(),
                if (r != null) _ScoreBadge(score: r.score),
              ],
            ),
            const SizedBox(height: 6),
            if (r != null)
              HighlightedText(text: paragraph.text, hits: r.techniques)
            else if (finished)
              Text(paragraph.text, style: theme.textTheme.bodyLarge)
            else ...[
              Text(
                l.paragraphPending(paragraph.p),
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 4),
              const ShimmerLines(),
            ],
          ],
        ),
      ),
    );
  }
}

class _ScoreBadge extends StatelessWidget {
  const _ScoreBadge({required this.score});

  final int score;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = temperatureColor(score);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c),
      ),
      child: Text(
        l.paragraphScore(score),
        style: Theme.of(context).textTheme.labelSmall,
      ),
    );
  }
}

/// Paragraph text with tappable highlights for technique quotes. Overlapping
/// quotes are drawn darker; a tap lists every technique covering that run.
class HighlightedText extends StatefulWidget {
  const HighlightedText({super.key, required this.text, required this.hits});

  final String text;
  final List<TechniqueHit> hits;

  @override
  State<HighlightedText> createState() => _HighlightedTextState();
}

class _HighlightedTextState extends State<HighlightedText> {
  final _recognizers = <TapGestureRecognizer>[];

  void _disposeRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _disposeRecognizers();
    final theme = Theme.of(context);
    final base = theme.textTheme.bodyLarge ?? const TextStyle();
    final hl = theme.colorScheme.tertiary;
    final segments = buildHighlightSegments(widget.text, widget.hits);
    final spans = <InlineSpan>[];
    for (final s in segments) {
      final text = s.textOf(widget.text);
      if (!s.highlighted) {
        spans.add(TextSpan(text: text));
        continue;
      }
      final recognizer = TapGestureRecognizer()
        ..onTap = () => showTechniqueSheet(context, s.hits);
      _recognizers.add(recognizer);
      final alpha = (0.18 + 0.14 * (s.hits.length - 1)).clamp(0.18, 0.6);
      spans.add(
        TextSpan(
          text: text,
          recognizer: recognizer,
          style: TextStyle(
            backgroundColor: hl.withValues(alpha: alpha),
            decoration: TextDecoration.underline,
            decorationColor: hl,
            decorationStyle: TextDecorationStyle.dotted,
          ),
        ),
      );
    }
    return Text.rich(
      TextSpan(style: base, children: spans),
      key: const Key('highlighted-text'),
    );
  }
}
