import 'package:flutter/material.dart';

import '../api/models.dart';
import '../l10n/app_localizations.dart';
import '../l10n/labels.dart';

/// Bottom sheet listing the techniques found in a tapped passage.
Future<void> showTechniqueSheet(BuildContext context, List<TechniqueHit> hits) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) =>
        _Sheet(children: [for (final h in hits) _HitTile(hit: h)]),
  );
}

/// Bottom sheet explaining a technique without a specific quote.
Future<void> showTechniqueInfoSheet(BuildContext context, String technique) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) =>
        _Sheet(children: [_Explanation(technique: technique)]),
  );
}

class _Sheet extends StatelessWidget {
  const _Sheet({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          children: [
            ...children,
            const SizedBox(height: 8),
            Text(l.sheetNote, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _Explanation extends StatelessWidget {
  const _Explanation({required this.technique});

  final String technique;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(techniqueName(l, technique), style: theme.textTheme.titleLarge),
        const SizedBox(height: 6),
        Text(techniqueInfo(l, technique), style: theme.textTheme.bodyMedium),
      ],
    );
  }
}

class _HitTile extends StatelessWidget {
  const _HitTile({required this.hit});

  final TechniqueHit hit;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final confidence = hit.confidence;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Explanation(technique: hit.technique),
          if (hit.quote.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(l.sheetQuoteLabel, style: theme.textTheme.labelMedium),
            const SizedBox(height: 4),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(color: theme.colorScheme.primary, width: 3),
                ),
                color: theme.colorScheme.surfaceContainerHigh,
              ),
              child: Text(
                hit.quote,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ],
          if (confidence != null) ...[
            const SizedBox(height: 6),
            Text(
              l.techniqueConfidence((confidence * 100).round()),
              style: theme.textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}
