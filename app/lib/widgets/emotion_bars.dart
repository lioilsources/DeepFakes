import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../l10n/labels.dart';

/// Horizontal bars for emotion intensities 0–1.
class EmotionBars extends StatelessWidget {
  const EmotionBars({super.key, required this.emotions});

  final Map<String, double> emotions;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final keys = [
      ...emotionKeys.where(emotions.containsKey),
      ...emotions.keys.where((k) => !emotionKeys.contains(k)),
    ];
    return Column(
      children: [
        for (final k in keys)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                SizedBox(
                  width: 110,
                  child: Text(
                    emotionName(l, k),
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: emotions[k]!.clamp(0.0, 1.0),
                      minHeight: 10,
                      backgroundColor:
                          theme.colorScheme.surfaceContainerHighest,
                    ),
                  ),
                ),
                SizedBox(
                  width: 44,
                  child: Text(
                    '${(emotions[k]! * 100).round()} %',
                    textAlign: TextAlign.end,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
