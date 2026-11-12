import 'package:flutter/material.dart';

/// Neutral-to-warm scale. Deliberately avoids a green/red "good/bad" reading:
/// temperature is not a verdict.
Color temperatureColor(int score) {
  const cool = Color(0xFF4F8A8B);
  const mid = Color(0xFFE0A030);
  const hot = Color(0xFFD9592B);
  final t = (score.clamp(0, 100)) / 100.0;
  return t < 0.5
      ? Color.lerp(cool, mid, t * 2)!
      : Color.lerp(mid, hot, (t - 0.5) * 2)!;
}
