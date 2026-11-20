part of '../main.dart';

/// Push a full-screen page with the signature slide + fade transition
/// (reversed automatically on pop).
void pushMidePage(BuildContext context, Widget page) {
  Navigator.of(context).push(
    PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 340),
      reverseTransitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (_, __, ___) => page,
      transitionsBuilder: (_, animation, __, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.06),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
    ),
  );
}

class _AppHeader extends StatelessWidget {
  const _AppHeader({
    required this.image,
    required this.title,
    this.version,
    this.actions = const [],
    this.leading,
  });

  /// Optional widget placed before the icon (a back arrow on pushed pages).
  final Widget? leading;

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
        if (leading != null) leading!,
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
                  // The product name is the header's anchor: set big, heavy
                  // and wide-tracked like the splash wordmark. Flexible keeps
                  // it from fighting the version chip on narrow screens.
                  Flexible(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: scheme.onSurface,
                              fontSize: 30,
                              height: 1.0,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.6,
                            ),
                          ),
                        ),
                        // The brand mark terminates the product name only —
                        // section headers like "MEarn" or "Мира" keep none.
                        if (title == 'MIDE') const _WordmarkDot(size: 30),
                      ],
                    ),
                  ),
                  if (version != null) ...[
                    const SizedBox(width: 8),
                    // The chip must give way to the wordmark: it shrinks a
                    // few percent on narrow phones instead of pushing the row
                    // past the edge or truncating "1.0.6" into "1.0…".
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: scheme.secondaryContainer,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            version!,
                            maxLines: 1,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: scheme.onSecondaryContainer,
                            ),
                          ),
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
  /// Tab value for the sliding pill: 0 = CRY, 1 = NPV, 2 = MEarn. The
  /// controller range extends to the last index (2.0) so the selection bubble
  /// can travel across every pill. Kept in sync with [_tabs] below.
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
    upperBound: 2.0,
  );

  /// Three destinations only: 3D and Clip live in the VPN header now.
  static const _tabs = <_TabSpec>[
    _TabSpec(icon: Icons.auto_awesome_rounded, label: 'CRY'),
    _TabSpec(icon: Icons.shield_rounded, label: 'NPV'),
    _TabSpec(icon: Icons.payments_rounded, label: 'Earn'),
  ];

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
      minimum: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Fit all pills into the available width; drop the text label on
          // narrow screens (icon-only) so nothing overflows. The reserved
          // 10dp is the container's 4dp padding on both sides plus its 1dp
          // border on both sides — leaving either out overflowed a 320dp
          // phone by exactly the missing pixels. The width is never floored
          // above what fits, or the floor itself would reintroduce the
          // overflow on very narrow screens.
          const chrome = 8.0 + 2.0;
          final available =
              (constraints.maxWidth - chrome - _gap * (_tabs.length - 1)) /
              _tabs.length;
          final pillWidth = available.clamp(0.0, 92.0);
          final showLabel = pillWidth >= 76;
          final unit = pillWidth + _gap;
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: scheme.outlineVariant.withValues(alpha: 0.6),
                  ),
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
                    // Each pill's foreground brightness: 1.0 selected, 0 otherwise.
                    double pillBrightness(int i) =>
                        (1.0 - (v - i).abs()).clamp(0.0, 1.0);
                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        // Sliding selection bubble.
                        Transform.translate(
                          offset: Offset(unit * v, 0),
                          child: Container(
                            width: pillWidth,
                            height: 34,
                            decoration: BoxDecoration(
                              color: scheme.primary,
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (var i = 0; i < _tabs.length; i++) ...[
                              if (i > 0) const SizedBox(width: _gap),
                              SizedBox(
                                width: pillWidth,
                                child: _TabPill(
                                  icon: _tabs[i].icon,
                                  label: _tabs[i].label,
                                  showLabel: showLabel,
                                  foreground: Color.lerp(
                                    scheme.onSurfaceVariant,
                                    scheme.onPrimary,
                                    pillBrightness(i),
                                  )!,
                                  onTap: () => _onTab(i),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Back affordance for sections that are pushed instead of tabbed.
class _BackArrow extends StatelessWidget {
  const _BackArrow();

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Назад',
      onPressed: () => Navigator.maybePop(context),
      icon: const Icon(Icons.arrow_back_rounded),
    );
  }
}

/// One bottom-bar destination: icon + short label.
class _TabSpec {
  const _TabSpec({required this.icon, required this.label});
  final IconData icon;
  final String label;
}

class _TabPill extends StatelessWidget {
  const _TabPill({
    required this.icon,
    required this.label,
    required this.showLabel,
    required this.foreground,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool showLabel;
  final Color foreground;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Bloody, semi-transparent press feedback: the pill tints crimson on
    // hold so a tap reads instantly even before the bubble finishes sliding.
    // The ripple is disabled — a crimson splash re-clipped the rounded rect
    // on every frame and was a visible source of jank while sliding.
    final blood = scheme.primary;
    return Semantics(
      button: true,
      label: showLabel ? null : label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          splashFactory: NoSplash.splashFactory,
          splashColor: Colors.transparent,
          highlightColor: blood.withValues(alpha: 0.16),
          hoverColor: blood.withValues(alpha: 0.10),
          child: SizedBox(
            height: 34,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 16, color: foreground),
                if (showLabel) ...[
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: foreground,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
