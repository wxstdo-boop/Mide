part of '../main.dart';

/// Smooth one-shot entrance: content fades in and glides up slightly on first
/// appearance (app launch). Re-running on rebuilds is avoided by keeping the
/// animation state inside the widget.
class _Entrance extends StatelessWidget {
  const _Entrance({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 620),
      curve: Curves.easeOutCubic,
      child: child,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, 22 * (1 - t)),
          child: child,
        ),
      ),
    );
  }
}

class _AppHeader extends StatelessWidget {
  const _AppHeader({
    required this.image,
    required this.title,
    this.version,
    this.actions = const [],
  });

  /// Real app icon asset (e.g. the Mide launcher icon).
  final String image;
  final String title;
  final String? version;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        SizedBox(
          width: 46,
          height: 46,
          child: Image.asset(image, fit: BoxFit.cover),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: scheme.onSurface,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
                  ),
                  if (version != null) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: scheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        version!,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: scheme.onSecondaryContainer,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        ...actions,
      ],
    );
  }
}

class _TabPillBar extends ConsumerStatefulWidget {
  const _TabPillBar();

  @override
  ConsumerState<_TabPillBar> createState() => _TabPillBarState();
}

class _TabPillBarState extends ConsumerState<_TabPillBar>
    with SingleTickerProviderStateMixin {
  /// Tab value for the sliding pill: 0.0 = AGI, 1.0 = NPV, 2.0 = MEarn.
  ///
  /// The range extends past the controller's default [0, 1] upper bound, so we
  /// raise `upperBound` to 2.0. Otherwise the value clamps to 1.0 and the
  /// selection bubble / highlight can never leave the NPV pill — MEarn looks
  /// "stuck on NPV" even though the tab is actually active.
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 480),
    upperBound: 2.0,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _anim.value = ref.read(appTabProvider).toDouble();
    });
  }

  void _onTab(int index) {
    ref.read(appTabProvider.notifier).select(index);
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  static const _pillWidth = 88.0;
  static const _gap = 4.0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    ref.watch(appTabProvider);
    ref.listen<int>(appTabProvider, (prev, next) {
      _anim.animateTo(next.toDouble(), curve: Curves.easeOutCubic);
    });
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                  color: scheme.outlineVariant.withValues(alpha: 0.6)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.10),
                  blurRadius: 14,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: AnimatedBuilder(
              animation: _anim,
              builder: (context, _) {
                final v = _anim.value;
                const unit = _pillWidth + _gap;
                // Each pill's foreground brightness: 1.0 when selected, 0 otherwise.
                double pillBrightness(int i) =>
                    (1.0 - (v - i).abs()).clamp(0.0, 1.0);
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // Sliding selection bubble.
                    Transform.translate(
                      offset: Offset(unit * v, 0),
                      child: Container(
                        width: _pillWidth,
                        height: 34,
                        decoration: BoxDecoration(
                          color: scheme.primary,
                          borderRadius: BorderRadius.circular(999),
                          boxShadow: [
                            BoxShadow(
                              color: scheme.primary.withValues(alpha: 0.35),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: _pillWidth,
                          child: _TabPill(
                            icon: Icons.auto_awesome_rounded,
                            label: 'AGI',
                            foreground: Color.lerp(
                              scheme.onSurfaceVariant,
                              scheme.onPrimary,
                              pillBrightness(0),
                            )!,
                            onTap: () => _onTab(0),
                          ),
                        ),
                        const SizedBox(width: _gap),
                        SizedBox(
                          width: _pillWidth,
                          child: _TabPill(
                            icon: Icons.shield_rounded,
                            label: 'NPV',
                            foreground: Color.lerp(
                              scheme.onSurfaceVariant,
                              scheme.onPrimary,
                              pillBrightness(1),
                            )!,
                            onTap: () => _onTab(1),
                          ),
                        ),
                        const SizedBox(width: _gap),
                        SizedBox(
                          width: _pillWidth,
                          child: _TabPill(
                            icon: Icons.payments_rounded,
                            label: 'MEarn',
                            foreground: Color.lerp(
                              scheme.onSurfaceVariant,
                              scheme.onPrimary,
                              pillBrightness(2),
                            )!,
                            onTap: () => _onTab(2),
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _TabPill extends StatelessWidget {
  const _TabPill({
    required this.icon,
    required this.label,
    required this.foreground,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color foreground;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // No explicit label: the inner [Text] already provides it, so screen
    // readers and the OS see "AGI"/"NPV" once instead of "AGI AGI".
    return Semantics(
      button: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: SizedBox(
            height: 34,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 16, color: foreground),
                const SizedBox(width: 5),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: foreground,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
