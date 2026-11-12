import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'temperature.dart';

/// Semicircular gauge for the overall text temperature 0–100, always shown
/// together with the "temperature ≠ truthfulness" disclaimer.
class TemperatureGauge extends StatelessWidget {
  const TemperatureGauge({super.key, this.score, this.provisional = false});

  /// Null while nothing has been measured yet.
  final int? score;
  final bool provisional;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final value = score;
    return Column(
      children: [
        Semantics(
          label: l.gaugeLabel,
          value: value?.toString() ?? l.gaugePending,
          child: SizedBox(
            width: 220,
            height: 124,
            child: CustomPaint(
              painter: _GaugePainter(
                value: value,
                track: theme.colorScheme.surfaceContainerHighest,
              ),
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      value?.toString() ?? '–',
                      key: const Key('gauge-score'),
                      style: theme.textTheme.displayMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: value == null ? null : temperatureColor(value),
                      ),
                    ),
                    Text(
                      value == null ? l.gaugePending : l.gaugeLabel,
                      style: theme.textTheme.labelLarge,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: SizedBox(
            width: 220,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(l.temperatureCalm, style: theme.textTheme.labelSmall),
                Text(l.temperatureHeated, style: theme.textTheme.labelSmall),
              ],
            ),
          ),
        ),
        if (provisional)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(l.gaugeProvisional, style: theme.textTheme.bodySmall),
          ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline,
                size: 20,
                color: theme.colorScheme.onSecondaryContainer,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l.temperatureDisclaimer,
                  key: const Key('temperature-disclaimer'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSecondaryContainer,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _GaugePainter extends CustomPainter {
  _GaugePainter({required this.value, required this.track});

  final int? value;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 16.0;
    final radius = math.min(size.width / 2, size.height) - stroke / 2;
    final center = Offset(size.width / 2, size.height - 4);
    final rect = Rect.fromCircle(center: center, radius: radius);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = track;
    canvas.drawArc(rect, math.pi, math.pi, false, base);
    final v = value;
    if (v == null || v <= 0) return;
    final sweep = math.pi * v.clamp(0, 100) / 100;
    final fill = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: math.pi,
        endAngle: 2 * math.pi,
        colors: [
          temperatureColor(0),
          temperatureColor(50),
          temperatureColor(100),
        ],
      ).createShader(rect);
    canvas.drawArc(rect, math.pi, sweep, false, fill);
  }

  @override
  bool shouldRepaint(_GaugePainter old) =>
      old.value != value || old.track != track;
}
