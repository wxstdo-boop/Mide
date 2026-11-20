part of 'ai_chat_ui.dart';

// ── Shimmer title ──────────────────────────────────────────────────────────

class _ShimmerTitle extends StatefulWidget {
  final String text;
  const _ShimmerTitle({required this.text});

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
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value;
        final center = -0.25 + 1.5 * t;
        const w = 0.2;
        final s1 = (center - w).clamp(0.0, 1.0);
        final s2 = (center - w * 0.45).clamp(0.0, 1.0);
        final s3 = center.clamp(0.0, 1.0);
        final s4 = (center + w * 0.45).clamp(0.0, 1.0);
        final s5 = (center + w).clamp(0.0, 1.0);
        final gloss = Color.alphaBlend(
          Colors.white.withValues(alpha: 0.85),
          red,
        );
        return ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (b) => LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [red, red, gloss, red, red],
            stops: [s1, s2, s3, s4, s5],
          ).createShader(b),
          child: Text(
            widget.text,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
            ),
          ),
        );
      },
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

// ── Provider badge (Horde / Pollinations) — cross-fades on change ─────────

class _ProviderBadge extends StatelessWidget {
  final String label;
  const _ProviderBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeInOut,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        // Layered, premium look: a soft gradient fill + a crisp outline +
        // a subtle inner top highlight that reads as glassy/expensive.
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.primaryContainer.withValues(alpha: 0.9),
            scheme.surfaceContainerHighest,
          ],
        ),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: scheme.primary.withValues(alpha: 0.4),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: scheme.primary.withValues(alpha: 0.22),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 500),
        transitionBuilder: (child, anim) => FadeTransition(
          opacity: anim,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.9, end: 1.0).animate(anim),
            child: child,
          ),
        ),
        child: Row(
          key: ValueKey('provider_$label'),
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: scheme.primary,
                borderRadius: BorderRadius.circular(7),
              ),
              child: Icon(
                Icons.smart_toy_rounded,
                size: 14,
                color: scheme.onPrimary,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.2,
                color: scheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── "MIDE" wordmark ──────────────────────────────────────────────────────

/// Small "Horde API" button next to the provider badge.
/// Opens a bottom sheet where the user pastes their free stablehorde.net
/// API key; the key is persisted in secure storage and injected into the
/// rotation on the next request.
class _HordeKeyButton extends ConsumerWidget {
  const _HordeKeyButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final keySet = ref.watch(hordeKeyProvider).trim().isNotEmpty;
    return GestureDetector(
      onTap: () => _showKeySheet(context, ref),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: keySet
                ? [
                    scheme.primaryContainer,
                    scheme.primary.withValues(alpha: 0.55),
                  ]
                : [scheme.surfaceContainerHighest, scheme.surfaceContainerHigh],
          ),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: keySet
                ? scheme.primary.withValues(alpha: 0.6)
                : scheme.outlineVariant.withValues(alpha: 0.6),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: keySet
                  ? scheme.primary.withValues(alpha: 0.28)
                  : Colors.black.withValues(alpha: 0.12),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: keySet
                    ? scheme.onPrimaryContainer
                    : scheme.primary.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(7),
              ),
              child: Icon(
                Icons.key_rounded,
                size: 14,
                color: keySet ? scheme.onPrimaryContainer : scheme.primary,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'Horde',
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.2,
                color: keySet
                    ? scheme.onPrimaryContainer
                    : scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showKeySheet(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final current = ref.read(hordeKeyProvider);
    final ctrl = TextEditingController(text: current);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: scheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 16),
              Text(
                'Horde API-ключ (бесплатно)',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: scheme.onSurface,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Зарегистрируйся на stablehorde.net (без карты) и вставь ключ —\n'
                'Horde станет основным провайдером.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.4,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: TextField(
                  controller: ctrl,
                  obscureText: true,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'API-ключ',
                    hintText: 'например: a1b2c3…',
                    prefixIcon: Icon(Icons.vpn_key_rounded),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        onPressed: () {
                          ref
                              .read(hordeKeyProvider.notifier)
                              .set(ctrl.text.trim());
                          Navigator.pop(ctx);
                        },
                        child: const Text('Сохранить'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          ref.read(hordeKeyProvider.notifier).clear();
                          Navigator.pop(ctx);
                        },
                        child: Text(
                          'Удалить',
                          style: TextStyle(color: scheme.error),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }
}

class _MideBrand extends StatelessWidget {
  const _MideBrand({this.fontSize = 20, this.subtitle});

  /// Larger brand for the top-center placement.
  final double fontSize;

  /// Optional disclaimer line shown under the brand when centered.
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final brand = Text(
      'MIDE',
      style: TextStyle(
        color: scheme.onSurface,
        fontSize: fontSize,
        fontWeight: FontWeight.w900,
        letterSpacing: 5,
        height: 1.0,
      ),
    );

    if (subtitle == null) return brand;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        brand,
        const SizedBox(height: 6),
        Text(
          subtitle!,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            fontStyle: FontStyle.italic,
            letterSpacing: 0.3,
            color: scheme.onSurfaceVariant.withValues(alpha: 0.55),
          ),
        ),
      ],
    );
  }
}
