import 'package:flutter/material.dart';

/// Placeholder lines with a moving highlight. Static when the platform asks
/// to reduce motion.
class ShimmerLines extends StatefulWidget {
  const ShimmerLines({super.key, this.lines = 3});

  final int lines;

  @override
  State<ShimmerLines> createState() => _ShimmerLinesState();
}

class _ShimmerLinesState extends State<ShimmerLines>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final base = scheme.surfaceContainerHighest;
    final light = scheme.surface;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value * 3 - 1; // sweep from -1 to 2
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (rect) => LinearGradient(
            colors: [base, light, base],
            stops: [
              (t - 0.3).clamp(0.0, 1.0),
              t.clamp(0.0, 1.0),
              (t + 0.3).clamp(0.0, 1.0),
            ],
          ).createShader(rect),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < widget.lines; i++)
                Container(
                  height: 12,
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  width: i == widget.lines - 1 ? 160 : double.infinity,
                  decoration: BoxDecoration(
                    color: base,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
