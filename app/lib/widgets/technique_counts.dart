import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../l10n/labels.dart';
import 'technique_sheet.dart';

/// Chips with how often each technique was found. Tap shows its explanation.
class TechniqueCounts extends StatelessWidget {
  const TechniqueCounts({super.key, required this.counts});

  final Map<String, int> counts;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    if (counts.isEmpty) {
      return Text(
        l.techniquesNone,
        style: Theme.of(context).textTheme.bodyMedium,
      );
    }
    final entries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final e in entries)
          ActionChip(
            avatar: CircleAvatar(child: Text('${e.value}')),
            label: Text(techniqueName(l, e.key)),
            onPressed: () => showTechniqueInfoSheet(context, e.key),
          ),
      ],
    );
  }
}
