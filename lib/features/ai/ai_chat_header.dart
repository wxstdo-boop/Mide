part of 'ai_chat_ui.dart';

// ── Shimmer title ──────────────────────────────────────────────────────────

class _ShimmerTitle extends StatefulWidget {
  final String text;
  final double fontSize;
  const _ShimmerTitle({required this.text, this.fontSize = 22});

  @override
  State<_ShimmerTitle> createState() => _ShimmerTitleState();
}

class _ShimmerTitleState extends State<_ShimmerTitle>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final red = Theme.of(context).colorScheme.error;
    final gloss = Color.alphaBlend(Colors.white.withValues(alpha: 0.85), red);

    // The red glow is drawn as text shadows on the same Text rather than a
    // second blurred copy: duplicating the string made screen readers announce
    // it twice and doubled the text in widget tests. The shader clamps outside
    // the glyph box, so the shadows still read as a halo.
    final text = Text(
      widget.text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: widget.fontSize,
        fontWeight: FontWeight.w900,
        letterSpacing: 0.4,
        color: red,
        shadows: [
          Shadow(color: red.withValues(alpha: 0.9), blurRadius: 16),
          Shadow(color: red.withValues(alpha: 0.6), blurRadius: 32),
        ],
      ),
    );

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _c,
        child: text,
        builder: (context, child) {
          final t = _c.value;
          final center = -0.25 + 1.5 * t;
          const w = 0.2;
          final s1 = (center - w).clamp(0.0, 1.0);
          final s2 = (center - w * 0.45).clamp(0.0, 1.0);
          final s3 = center.clamp(0.0, 1.0);
          final s4 = (center + w * 0.45).clamp(0.0, 1.0);
          final s5 = (center + w).clamp(0.0, 1.0);
          return ShaderMask(
            blendMode: BlendMode.srcIn,
            shaderCallback: (b) => LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [red, red, gloss, red, red],
              stops: [s1, s2, s3, s4, s5],
            ).createShader(b),
            child: child,
          );
        },
      ),
    );
  }
}

// ── M.AI badge ─────────────────────────────────────────────────────────────

class _Badge extends StatelessWidget {
  final String text;
  const _Badge({required this.text});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: scheme.onSecondaryContainer,
        ),
      ),
    );
  }
}
