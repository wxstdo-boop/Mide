// Mide — FOSS VPN client. Material You (M3) interface with "bloody" themes.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'core/nav/app_tab_provider.dart';
import 'core/theme/mide_theme.dart';
import 'core/theme/theme_providers.dart';
import 'features/ai/ai_chat_ui.dart';
import 'features/vpn/providers/vpn_providers.dart';
import 'features/updater/github_updater.dart';
import 'features/updater/updater_types.dart';
import 'features/vpn/vpn_settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Portrait only - no auto-rotation.
  await SystemChrome.setPreferredOrientations(
      [DeviceOrientation.portraitUp]);
  // Resolve the persisted theme *before* the first frame so the app never
  // flashes the default (dark) palette and then "lightens" up. Seeding the
  // provider with the authoritative value means the very first paint already
  // shows the saved theme.
  final seededTheme = await ThemeChoiceNotifier.loadPersisted();
  // Reopen the last-used section instead of flashing the default tab.
  final seededTab = await AppTabNotifier.loadPersisted();
  runApp(
    ProviderScope(
      overrides: [
        themeChoiceProvider.overrideWith(
          () => ThemeChoiceNotifier(seed: seededTheme),
        ),
        appTabProvider.overrideWith(
          () => AppTabNotifier(seed: seededTab),
        ),
      ],
      child: const MideApp(),
    ),
  );
}

/// Smooth elastic scrolling everywhere (content slides with the finger and
/// springs back on release instead of the hard platform overscroll glow).
class _BouncyScrollBehavior extends MaterialScrollBehavior {
  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      );
}

class MideApp extends ConsumerWidget {
  const MideApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final choice = ref.watch(themeChoiceProvider);
    return MaterialApp(
      title: 'Mide',
      debugShowCheckedModeBanner: false,
      scrollBehavior: _BouncyScrollBehavior(),
      theme: buildBloodyTheme(Brightness.light),
      darkTheme: buildBloodyTheme(Brightness.dark),
      themeMode: choice.isDark ? ThemeMode.dark : ThemeMode.light,
      themeAnimationDuration: const Duration(milliseconds: 500),
      themeAnimationCurve: Curves.easeInOutCubic,
      home: const _SplashShell(child: HomePage()),
    );
  }
}

/// A Flutter-drawn splash that sits over the already-built [child]. The
/// real app renders behind it from frame one (so there is no white flash
/// when the splash lifts), then the full-bleed themed backdrop with the
/// centered emblem eases out into the section you last opened.
///
/// The backdrop is opaque and *never* transformed: an earlier version wrapped
/// the whole overlay (background included) in a `Transform.scale(0.96)`, so for
/// the first ~1.5s the app peeked out through a 2% margin on every edge — the
/// "splash does not cover the whole background" report. Only the emblem
/// animates now.
class _SplashShell extends StatefulWidget {
  const _SplashShell({required this.child});

  final Widget child;

  @override
  State<_SplashShell> createState() => _SplashShellState();
}

class _SplashShellState extends State<_SplashShell>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2800),
  )..forward();

  bool _gone = false;

  @override
  void initState() {
    super.initState();
    // Drop the overlay the moment the exit animation finishes so it stops
    // consuming a composite layer.
    _c.addStatusListener((s) {
      if (s == AnimationStatus.completed && mounted) setState(() => _gone = true);
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Hold the splash fully visible for the first ~60%, then ease it out.
    final exit = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.0), weight: 55),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 45),
    ]).animate(CurvedAnimation(parent: _c, curve: Curves.easeInOutCubic));
    // Emblem-only scale: settles at 0.92, then drifts up as the splash lifts.
    final scale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.92, end: 0.92), weight: 55),
      TweenSequenceItem(tween: Tween(begin: 0.92, end: 1.06), weight: 45),
    ]).animate(CurvedAnimation(parent: _c, curve: Curves.easeInOutCubic));

    // Full-bleed backdrop: opaque `surface` under a crimson-tinted gradient
    // that mirrors `HomePage`, so the hand-off from the native launch window
    // to this overlay to the app is one continuous surface.
    final background = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Color.alphaBlend(scheme.primary.withValues(alpha: 0.18), scheme.surface),
        scheme.surface,
      ],
      stops: const [0.0, 0.5],
    );

    // The emblem fades in over the first ~30% of the timeline, then holds, then
    // breathes slightly while the backdrop lifts away.
    final emblemOpacity = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 30),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.0), weight: 70),
    ]).animate(CurvedAnimation(parent: _c, curve: Curves.easeOutCubic));

    return Stack(
      fit: StackFit.expand,
      children: [
        // The real app sits behind from the very first frame.
        widget.child,
        // The splash overlay fades out, then removes itself.
        if (!_gone)
          Positioned.fill(
            child: IgnorePointer(
              child: FadeTransition(
                opacity: exit,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Opaque backdrop. `Positioned.fill` + `StackFit.expand`
                    // make it span the whole window, including the strips
                    // behind the status and navigation bars, so nothing of
                    // the app below can show through.
                    ColoredBox(
                      color: scheme.surface,
                      child: DecoratedBox(
                        decoration: BoxDecoration(gradient: background),
                      ),
                    ),
                    Center(
                      child: FadeTransition(
                        opacity: emblemOpacity,
                        // Scale is applied to the emblem alone — never to the
                        // backdrop, or the edges would expose the app.
                        child: Transform.scale(
                          scale: scale.value,
                          child: _SplashEmblem(scheme: scheme),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Launch emblem: the Mide glyph on a light squircle chip (the same shape and
/// palette as the launcher icon, so it reads identically in the light and the
/// dark theme) with a themed halo behind it and the wordmark underneath.
///
/// Why a separate asset instead of `mide.png`: the launcher PNG is a *squircle
/// plate* with the glyph already baked in and shifted towards the top-right by
/// the sparkle. Clipping that plate into a circle (the old `ClipOval`) cut the
/// corners off and left the glyph visibly off-centre. `mide_mark.png` is the
/// bare glyph, pre-cropped so the teardrop is exactly centred on a square
/// canvas (see `.agnes/work/make_mark.py`), and the chip below repeats the
/// icon's 30% corner radius — glyph and frame can no longer drift apart.
class _SplashEmblem extends StatelessWidget {
  const _SplashEmblem({required this.scheme});

  final ColorScheme scheme;

  /// Edge of the squircle chip.
  static const double _size = 152;

  /// Same squircle radius as the launcher icon, so the splash emblem and the
  /// installed app icon are the same silhouette.
  static const double _radius = _size * 0.30;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: _size,
          height: _size,
          child: DecoratedBox(
            // Halo + drop shadow live on the outer box so the clip below does
            // not cut them off.
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(_radius),
              boxShadow: [
                BoxShadow(
                  color: scheme.primary.withValues(alpha: isDark ? 0.45 : 0.26),
                  blurRadius: 46,
                  spreadRadius: -10,
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.55 : 0.16),
                  blurRadius: 24,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(_radius),
              child: Container(
                decoration: const BoxDecoration(
                  // Always light: the glyph is deep navy, which would vanish
                  // on a dark chip.
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFFFFFFF), Color(0xFFEBEEF6)],
                  ),
                ),
                foregroundDecoration: BoxDecoration(
                  border: Border.all(
                    color: scheme.primary.withValues(alpha: 0.20),
                    width: 1.2,
                  ),
                  borderRadius: BorderRadius.circular(_radius),
                ),
                // Equal padding on all four sides + a square `contain` fit on
                // an asset that is already centred => the glyph is optically
                // centred in the chip, at any density.
                padding: const EdgeInsets.all(_size * 0.155),
                child: Image.asset(
                  'assets/icon/mide_mark.png',
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
        ),
        // 32dp clears the chip's blurred drop shadow (12dp offset + 12dp blur
        // reach) so the glow never bleeds into the wordmark.
        const SizedBox(height: 32),
        Text(
          'Mide',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            letterSpacing: 4,
            color: scheme.onSurface.withValues(alpha: 0.78),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Ада_',
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
            color: scheme.onSurfaceVariant.withValues(alpha: 0.85),
          ),
        ),
      ],
    );
  }
}

/// Shell with the bottom pill navigation: AGI (AI), NPV (VPN), MEarn (crypto).
class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  @override
  Widget build(BuildContext context) {
    // Active tab is persisted, so the app reopens on the section you left.
    final scheme = Theme.of(context).colorScheme;
    final tab = ref.watch(appTabProvider);

    // Direction-independent, fast-tap-safe transition: content always
    // fades, lifts up slightly and settles from a tiny scale. Because the
    // motion no longer flips between left/right based on which way you
    // swiped, rapid AGI↔NPV↔MEarn tapping can no longer make the panels
    // slide "there and back again" — they just cross-fade in place.
    return Scaffold(
      backgroundColor: scheme.surface,
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color.alphaBlend(
                scheme.primary.withValues(alpha: 0.16),
                scheme.surface,
              ),
              scheme.surface,
            ],
            stops: const [0.0, 0.42],
          ),
        ),
        child: _Entrance(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 420),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            // Let the exiting panel finish animating before the entering one
            // takes over, so fast taps stack instead of snapping.
            layoutBuilder: (currentChild, previousChildren) {
              return Stack(
                fit: StackFit.passthrough,
                alignment: Alignment.topLeft,
                clipBehavior: Clip.none,
                children: [
                  ...previousChildren,
                  if (currentChild != null) currentChild,
                ],
              );
            },
            transitionBuilder: (child, animation) {
              final curved = CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
                reverseCurve: Curves.easeInCubic,
              );
              // Consistent gentle lift + fade + settle — no horizontal flip.
              return FadeTransition(
                opacity: curved,
                child: SlideTransition(
                  position:
                      Tween<Offset>(begin: const Offset(0.0, 0.03), end: Offset.zero)
                          .animate(curved),
                  child: ScaleTransition(
                    scale: Tween<double>(begin: 0.985, end: 1).animate(curved),
                    child: child,
                  ),
                ),
              );
            },
            child: switch (tab) {
                0 => const AiTab(key: ValueKey('agi')),
                1 => const VpnTab(key: ValueKey('vpn')),
                _ => const MEarnTab(key: ValueKey('mearn')),
              },
          ),
        ),
      ),
      bottomNavigationBar: const _TabPillBar(),
    );
  }
}

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
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
              border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
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

/// AGI tab — remote AI assistant. Placeholder for now, will be fleshed out later.

/// NPV tab — the VPN client.
class VpnTab extends ConsumerWidget {
  const VpnTab({super.key});

  Future<void> _openMail(BuildContext context) async {
    const email = 'hello@mide.app';
    final uri = Uri(
      scheme: 'mailto',
      path: email,
      queryParameters: {'subject': 'Mide VPN'},
    );
    try {
      await launchUrl(uri);
    } catch (_) {}
  }

  void _showSettings(BuildContext context) {
    _pushPage(context, const SettingsPage());

  }

  /// Push a full-screen page with the signature slide + fade + scale transition
  /// (reversed automatically on pop).
  static void _pushPage(BuildContext context, Widget page) {
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 480),
        reverseTransitionDuration: const Duration(milliseconds: 400),
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
                begin: const Offset(0, 0.09),
                end: Offset.zero,
              ).animate(curved),
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.97, end: 1).animate(curved),
                child: child,
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            // The tunnel list is a static preset now; re-read the engine stage
            // so the card reflects the native VPN state on pull-to-refresh.
            await ref.read(vpnConnectionStateProvider.notifier).stageRefresh();
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _AppHeader(
                  image: 'assets/icon/mide.png',
                  title: 'Mide',
                  version: '0.75b',
                  actions: [
                    IconButton.filledTonal(
                      onPressed: () => _openMail(context),
                      icon: const Icon(Icons.mail_rounded),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      onPressed: () => _showSettings(context),
                      icon: const Icon(Icons.settings_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                const _VpnToggleCard(),
                const SizedBox(height: 20),
                const ServerListSection(),
                if (ref.watch(vpnConnectionStateProvider).isConnected) ...[
                  const SizedBox(height: 16),
                  const ConnectionInfoCard(),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}


class ServerListSection extends ConsumerWidget {
  const ServerListSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final servers = ref.watch(vpnServersProvider);
    final selectedId = ref.watch(selectedServerIdProvider);
    final vpnState = ref.watch(vpnConnectionStateProvider);

    return Column(
      key: const ValueKey('servers-data'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
          Row(
            children: [
              Text(
                'Серверы',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurface,
                ),
              ),
              if (servers.isNotEmpty) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${servers.length}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          if (servers.isEmpty)
            const _EmptyServers()
          else
            ...servers.map(
              (s) => _ServerTile(
                server: s,
                isSelected: s.id == selectedId,
                isCurrent: vpnState.isConnected && vpnState.serverId == s.id,
                isBusy: vpnState.isConnecting && vpnState.serverId == s.id,
                onTap: () => ref.read(selectedServerIdProvider.notifier).state = s.id,
                onToggle: () =>
                    ref.read(vpnConnectionStateProvider.notifier).toggle(s.id),
              ),
            ),
        ],
    );
  }
}

class _ServerTile extends StatelessWidget {
  const _ServerTile({
    required this.server,
    required this.isSelected,
    required this.isCurrent,
    required this.isBusy,
    required this.onTap,
    required this.onToggle,
  });

  final VpnServer server;
  final bool isSelected;
  final bool isCurrent;
  final bool isBusy;
  final VoidCallback onTap;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final mide = context.mideTheme;

    final parts = <String>[
      if (server.country != null && server.country!.isNotEmpty) server.country!,
      if (server.ping > 0) '${server.ping} мс',
    ];
    final subtitle = parts.join(' • ');

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: isSelected ? scheme.primaryContainer : scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isSelected
                    ? scheme.primary
                    : scheme.outlineVariant.withValues(alpha: 0.5),
                width: isSelected ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? scheme.primary.withValues(alpha: 0.12)
                        : scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    switch (server.id) {
                      'warp' => Icons.bolt_rounded,
                      'v2nodes' => Icons.hub_rounded,
                      // `Icons.shield_locked_rounded` does not exist in Flutter — it broke the
                      // whole app at compile time. `vpn_lock` is the closest
                      // real icon.
                      'reality' => Icons.vpn_lock_rounded,
                      _ => Icons.dns_rounded,
                    },
                    size: 22,
                    color: isSelected ? scheme.primary : scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        server.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: scheme.onSurface,
                        ),
                      ),
                      if (subtitle.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (isCurrent) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: mide.successContainer,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      'В сети',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: mide.onSuccessContainer,
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: 6),
                // Per-server connect / disconnect toggle.
                IconButton.filledTonal(
                  isSelected: isCurrent,
                  onPressed: isBusy ? null : onToggle,
                  style: IconButton.styleFrom(
                    backgroundColor: isCurrent
                        ? scheme.errorContainer
                        : scheme.primary.withValues(alpha: 0.12),
                    foregroundColor: isCurrent
                        ? scheme.onErrorContainer
                        : scheme.primary,
                    disabledBackgroundColor: scheme.surfaceContainerHighest,
                  ),
                  icon: isBusy
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: scheme.primary,
                          ),
                        )
                      : Icon(
                          isCurrent
                              ? Icons.power_settings_new_rounded
                              : Icons.play_arrow_rounded,
                          size: 20,
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

class _EmptyServers extends StatelessWidget {
  const _EmptyServers();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36),
      child: Center(
        child: Column(
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.dns_rounded,
                size: 32,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Серверы не найдены',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: scheme.onSurface),
            ),
            const SizedBox(height: 4),
            Text(
              'Проверьте API-ключ и адрес провайдера в настройках',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}


class ConnectionInfoCard extends ConsumerWidget {
  const ConnectionInfoCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final vpnState = ref.watch(vpnConnectionStateProvider);
    final latency = ref.watch(vpnMetricsProvider).valueOrNull?.latencyMs;

    Widget cell(String label, String value) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: scheme.onSurface,
            ),
          ),
        ],
      );
    }

    Widget divider() => Container(
          width: 1,
          height: 36,
          margin: const EdgeInsets.symmetric(horizontal: 16),
          color: scheme.outlineVariant.withValues(alpha: 0.6),
        );

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        child: Row(
          children: [
            Expanded(child: cell('IP-адрес', vpnState.ipAddress ?? '—')),
            divider(),
            Expanded(child: cell('Протокол', vpnState.protocol)),
            divider(),
            Expanded(child: cell('Задержка', latency != null ? '$latency мс' : '—')),
          ],
        ),
      ),
    );
  }
}

/// Settings: theme carousel + entry point to the VPN connection setup.
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header.
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.keyboard_arrow_down_rounded),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Настройки',
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        Text(
                          'Тема и обновления',
                          style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                children: [
                  const _SectionTitle(
                    icon: Icons.palette_rounded,
                    title: 'Тема',
                    subtitle: 'Листай карусель — тема меняется сразу',
                  ),
                  const SizedBox(height: 14),
                  const ThemeCarousel(),
                  const SizedBox(height: 28),
                  const _SectionTitle(
                    icon: Icons.system_update_alt_rounded,
                    title: 'Обновления',
                    subtitle: 'Проверка и установка нового билда из GitHub',
                  ),
                  const SizedBox(height: 14),
                  const _UpdateSection(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Connection setup: subscription URL + optional API key.
class SetupVpnPage extends ConsumerStatefulWidget {
  const SetupVpnPage({super.key});

  @override
  ConsumerState<SetupVpnPage> createState() => _SetupVpnPageState();
}

class _SetupVpnPageState extends ConsumerState<SetupVpnPage> {
  final _urlCtrl = TextEditingController();
  final _keyCtrl = TextEditingController();
  bool _showAdvanced = false;
  bool _obscureKey = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _keyCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final settings = await ref.read(vpnSettingsProvider.future);
    if (!mounted) return;
    _urlCtrl.text = settings.baseUrl;
    _keyCtrl.text = settings.apiKey;
  }

  Future<void> _save() async {
    final settings = VpnSettings(
      apiKey: _keyCtrl.text.trim(),
      baseUrl: _urlCtrl.text.trim().isEmpty
          ? VpnSettingsStore.defaultBaseUrl
          : _urlCtrl.text.trim(),
    );
    setState(() => _saving = true);
    try {
      await ref.read(vpnSettingsStoreProvider).save(settings);
      ref.invalidate(vpnSettingsProvider);
      ref.invalidate(vpnServersProvider);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      // Silent: key remains in the field for re-entry.
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _clear() async {
    await ref.read(vpnSettingsStoreProvider).clear();
    ref.invalidate(vpnSettingsProvider);
    ref.invalidate(vpnServersProvider);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header.
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Настройка VPN',
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        Text(
                          'Подключение к провайдеру',
                          style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
                children: [
                  // Subscription URL hero card.
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          scheme.primary.withValues(alpha: 0.16),
                          scheme.primary.withValues(alpha: 0.04),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: scheme.primary.withValues(alpha: 0.25)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: scheme.primary,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(Icons.rss_feed_rounded, color: scheme.onPrimary),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'URL подписки',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: scheme.onSurface,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Вставь ссылку на серверы провайдера — они появятся во вкладке NPV',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  height: 1.35,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _urlCtrl,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'URL подписки',
                      hintText: 'https://provider.example.com',
                      prefixIcon: Icon(Icons.link_rounded),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Advanced: API key (optional).
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => setState(() => _showAdvanced = !_showAdvanced),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            Icon(
                              _showAdvanced
                                  ? Icons.expand_less_rounded
                                  : Icons.expand_more_rounded,
                              size: 20,
                              color: scheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'API-ключ (если требуется)',
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  AnimatedCrossFade(
                    duration: const Duration(milliseconds: 280),
                    crossFadeState: _showAdvanced
                        ? CrossFadeState.showSecond
                        : CrossFadeState.showFirst,
                    firstChild: const SizedBox(width: double.infinity),
                    secondChild: Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: TextField(
                        controller: _keyCtrl,
                        obscureText: _obscureKey,
                        autocorrect: false,
                        enableSuggestions: false,
                        decoration: InputDecoration(
                          labelText: 'API-ключ',
                          prefixIcon: const Icon(Icons.vpn_key_rounded),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscureKey
                                  ? Icons.visibility_rounded
                                  : Icons.visibility_off_rounded,
                              size: 20,
                            ),
                            onPressed: () =>
                                setState(() => _obscureKey = !_obscureKey),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.cloud_download_rounded),
                      label: const Text('Получить серверы'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: TextButton.icon(
                      onPressed: _saving ? null : _clear,
                      icon: const Icon(Icons.delete_outline_rounded, size: 18),
                      label: const Text('Удалить ключ'),
                      style: TextButton.styleFrom(foregroundColor: scheme.error),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: scheme.secondaryContainer,
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(icon, size: 18, color: scheme.onSecondaryContainer),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: scheme.onSurface,
                ),
              ),
              Text(
                subtitle,
                style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Horizontal carousel of theme cards — swiping applies the theme instantly.
class ThemeCarousel extends ConsumerStatefulWidget {
  const ThemeCarousel({super.key});

  @override
  ConsumerState<ThemeCarousel> createState() => _ThemeCarouselState();
}

class _ThemeCarouselState extends ConsumerState<ThemeCarousel> {
  late final PageController _controller;
  late int _page;

  @override
  void initState() {
    super.initState();
    // Start the carousel on the page of the currently selected theme.
    // (Without initialPage the view opens on page 0, so the checkmark and
    // the centered card could disagree — the reported "checkmark on dark,
    // display on light" bug.)
    final initial = MideThemeChoice.values.indexOf(ref.read(themeChoiceProvider));
    _page = initial;
    _controller = PageController(viewportFraction: 0.86, initialPage: initial);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _select(int page) {
    setState(() => _page = page);
    ref.read(themeChoiceProvider.notifier).select(MideThemeChoice.values[page]);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final choice = ref.watch(themeChoiceProvider);
    final choiceIndex = MideThemeChoice.values.indexOf(choice);
    if (choiceIndex != _page) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_controller.hasClients) return;
        _controller.animateToPage(choiceIndex, duration: const Duration(milliseconds: 480), curve: Curves.easeInOutCubic);
        setState(() => _page = choiceIndex);
      });
    }
    return Column(
      children: [
        SizedBox(
          height: 176,
          child: PageView.builder(
            controller: _controller,
            itemCount: MideThemeChoice.values.length,
            onPageChanged: _select,
            itemBuilder: (context, index) {
              final item = MideThemeChoice.values[index];
              return _ThemeCard(
                choice: item,
                selected: choiceIndex == index,
                onTap: () {
                  _controller.animateToPage(
                    index,
                    duration: const Duration(milliseconds: 420),
                    curve: Curves.easeInOutCubic,
                  );

                },
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(MideThemeChoice.values.length, (i) {
            final active = i == _page;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 480),
              curve: Curves.easeInOutCubic,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: active ? 22 : 8,
              height: 8,
              decoration: BoxDecoration(
                color: active
                    ? scheme.primary
                    : scheme.outlineVariant.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(999),
              ),
            );
          }),
        ),
      ],
    );
  }
}

/// A single theme card with a live mini-preview of its palette.
class _ThemeCard extends StatelessWidget {
  const _ThemeCard({
    required this.choice,
    required this.selected,
    required this.onTap,
  });

  final MideThemeChoice choice;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: bloodySeed,
      brightness: choice.isDark ? Brightness.dark : Brightness.light,
    );
    return AnimatedContainer(
      duration: const Duration(milliseconds: 480),
      curve: Curves.easeInOutCubic,
      margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: selected
              ? scheme.primary
              : scheme.outlineVariant.withValues(alpha: 0.5),
          width: selected ? 2.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: selected
                ? scheme.primary.withValues(alpha: 0.25)
                : Colors.black.withValues(alpha: 0.05),
            blurRadius: selected ? 18 : 8,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(28),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(28),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [scheme.primary, scheme.tertiary],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: Icon(
                        Icons.colorize_rounded,
                        size: 20,
                        color: scheme.onPrimary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            choice.label,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: scheme.onSurface,
                            ),
                          ),
                          Text(
                            choice.subtitle,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 280),
                      curve: Curves.easeOutBack,
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: selected ? scheme.primary : Colors.transparent,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: selected ? scheme.primary : scheme.outlineVariant,
                        ),
                      ),
                      child: selected
                          ? Icon(Icons.check_rounded, size: 16, color: scheme.onPrimary)
                          : null,
                    ),
                  ],
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration:
                            BoxDecoration(color: scheme.primary, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Container(
                          height: 6,
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        width: 64,
                        height: 22,
                        decoration: BoxDecoration(
                          color: scheme.primary,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ],
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

// ---------------------------------------------------------------------------
// MEarn Tab — passive crypto / money farming
// ---------------------------------------------------------------------------

class MEarnTab extends StatelessWidget {
  const MEarnTab({super.key});

  static const _cards = <_EarnCardData>[
    _EarnCardData(
      icon: Icons.quiz_rounded,
      title: 'Анкетка',
      subtitle: 'Проходи опросы — получаешь рубли на карту. Простой заработок без вложений',
      url: 'https://anketka.ru',
      gradient: [Color(0xFFE91E63), Color(0xFF9C27B0)],
    ),
    _EarnCardData(
      icon: Icons.currency_bitcoin_rounded,
      title: 'Kryptex',
      subtitle: 'Майнишь крипту на своём ПК. Вывод на карту или BTC. Работает в РФ',
      url: 'https://kryptex.org',
      gradient: [Color(0xFFFF9800), Color(0xFFFF5722)],
    ),
    _EarnCardData(
      icon: Icons.hexagon_rounded,
      title: 'Honeygain',
      subtitle: 'Сдавай интернет — получаешь BTC. Работает в РФ, минимум 50 руб',
      url: 'https://honeygain.com',
      gradient: [Color(0xFFF59E0B), Color(0xFFD97706)],
    ),
    _EarnCardData(
      icon: Icons.hive_rounded,
      title: 'DataHive AI',
      subtitle: 'Децентрализованная биржа данных. Сдавай трафик — зарабатывай токены',
      url: 'https://datahive.ai',
      gradient: [Color(0xFF10B981), Color(0xFF3B82F6)],
    ),
    _EarnCardData(
      icon: Icons.water_drop_rounded,
      title: 'Pond AI',
      subtitle: 'Фарм токены за разметку данных для ИИ. Пассивный доход',
      url: 'https://pondai.io',
      gradient: [Color(0xFF0EA5E9), Color(0xFF6366F1)],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
          children: [
            _AppHeader(
              image: 'assets/icon/mide.png',
              title: 'MEarn',
              version: '0.75b',
              actions: [
                IconButton.filledTonal(
                  onPressed: () {},
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Quick stats row.
            Row(
              children: [
                _StatChip(
                  icon: Icons.trending_up_rounded,
                  label: '5 сервисов',
                  color: scheme.primary,
                ),
                const SizedBox(width: 8),
                _StatChip(
                  icon: Icons.circle,
                  label: 'Пассивный доход',
                  color: scheme.tertiary,
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              'Фарм и заработок',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Открой сервис, подключи — и капает пассивно',
              style: TextStyle(
                fontSize: 13,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            ..._cards.map((c) => _EarnCard(data: c)),
          ],
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _EarnCardData {
  const _EarnCardData({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.url,
    required this.gradient,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String url;
  final List<Color> gradient;
}

class _EarnCard extends StatelessWidget {
  const _EarnCard({required this.data});

  final _EarnCardData data;

  Future<void> _open(BuildContext context) async {
    final uri = Uri.parse(data.url);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: () => _open(context),
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: scheme.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            child: Row(
              children: [
                // Gradient icon container.
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: data.gradient,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    data.icon,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                // Text.
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        data.title,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: scheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        data.subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.35,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.open_in_new_rounded,
                  size: 18,
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}


// ── VPN toggle: a single clean ON/OFF control that drives a real tunnel ──
// On Windows the two V2Nodes entries run the bundled Xray core (free VLESS
// lists, screened for life before spawning); elsewhere WARP enrolls a
// WireGuard config. No import, no subscription, no API key either way.

class _VpnToggleCard extends ConsumerWidget {
  const _VpnToggleCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final state = ref.watch(vpnConnectionStateProvider);
    final conf = ref.watch(wgConfigProvider);

    final isConnected = state.isConnected;
    final isBusy = state.isConnecting;
    final denied = state.phase == VpnPhase.denied;
    final failed = state.phase == VpnPhase.failed;

    Future<void> handleToggle() async {
      final notifier = ref.read(vpnConnectionStateProvider.notifier);
      if (isConnected) {
        notifier.disconnect();
        return;
      }
      if (isBusy) return;
      notifier.toggle(ref.read(selectedServerIdProvider) ?? 'v2nodes');
    }

    // First-ever connect also provisions the tunnel (keygen + enrollment, or
    // screening free nodes), which is worth calling out so the pause doesn't
    // look like a hang.
    final xrayPath =
        state.serverId == 'v2nodes' || state.serverId == 'reality';
    final provisioning = isBusy &&
        state.phase == VpnPhase.connecting &&
        (xrayPath || conf.isEmpty);

    final (String title, String status) = isConnected
        ? ('VPN включён', 'Туннель работает · обход активен')
        : denied
            ? ('Разрешение отклонено',
                state.error ?? 'Система не дала VPN-разрешение')
            : failed
                ? ('Ошибка подключения', state.error ?? 'Туннель не запустился')
                : provisioning
                    ? (xrayPath
                        ? (state.serverId == 'reality'
                            ? ('Ищем живые Reality-узлы…',
                                'Перебираем VLESS Reality · список обновляется каждые 15 мин')
                            : ('Ищем живые узлы…',
                                'Перебираем бесплатные V2Nodes-узлы…'))
                        : ('Готовим туннель…',
                            'Бесплатная регистрация WireGuard-конфига…'))
                    : isBusy
                        ? (state.phase == VpnPhase.disconnecting
                            ? 'Выключаем…'
                            : 'Подключаем…',
                          'Открываем туннель…')
                        : ('VPN выключен', 'Готов к включению');

    final btnLabel = isConnected
        ? 'Выключить VPN'
        : isBusy
            ? (state.phase == VpnPhase.disconnecting ? 'Выключаем…' : 'Подключаем…')
            : 'Включить VPN';

    final accent = isConnected ? scheme.primary : scheme.error;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isConnected
              ? [scheme.primaryContainer, scheme.surfaceContainerHigh]
              : [scheme.surfaceContainerHigh, scheme.surfaceContainerHighest],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isConnected
              ? scheme.primary.withValues(alpha: 0.5)
              : scheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: isConnected
                      ? scheme.primary.withValues(alpha: 0.16)
                      : scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: isBusy
                    ? Center(
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5, color: accent,
                        ),
                      )
                    : Icon(
                        isConnected ? Icons.shield_rounded : Icons.vpn_key_rounded,
                        color: isConnected ? scheme.primary : scheme.onSurfaceVariant,
                        size: 24,
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: scheme.onSurface,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      status,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: (denied || failed ? scheme.error : scheme.onSurfaceVariant)
                            .withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: isBusy ? null : handleToggle,
              borderRadius: BorderRadius.circular(999),
              child: Container(
                width: double.infinity,
                height: 54,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: isConnected
                        ? [scheme.error, scheme.error.withValues(alpha: 0.85)]
                        : [scheme.primary, scheme.primary.withValues(alpha: 0.85)],
                  ),
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.35),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      isBusy
                          ? Icons.autorenew_rounded
                          : (isConnected
                                ? Icons.stop_rounded
                                : Icons.bolt_rounded),
                      color: isConnected ? scheme.onError : scheme.onPrimary,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      btnLabel,
                      style: TextStyle(
                        color: isConnected ? scheme.onError : scheme.onPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Settings: the "Обновления" section ────────────────────────────────────────

/// One-tap update: checks the latest GitHub release, downloads the Android
/// arm64 APK when needed, and opens Android's installer for confirmation.
class _UpdateSection extends StatefulWidget {
  const _UpdateSection();

  @override
  State<_UpdateSection> createState() => _UpdateSectionState();
}

class _UpdateSectionState extends State<_UpdateSection> {
  bool _checking = false;
  bool _installing = false;
  UpdateCheckResult? _result;

  bool get _busy => _checking || _installing;

  Future<void> _check() async {
    if (_busy) return;
    setState(() => _checking = true);
    try {
      final res = await githubUpdater.checkLatest();
      if (!mounted) return;
      setState(() {
        _result = res;
        if (res.hasUpdate) {
          _checking = false;
          _installing = true;
        }
      });
      if (res.hasUpdate) {
        final done = await githubUpdater.downloadAndInstall(res);
        if (mounted) setState(() => _result = done);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _result = UpdateCheckResult.failure('$e'));
      }
    } finally {
      if (mounted) {
        setState(() {
          _checking = false;
          _installing = false;
        });
      }
    }
  }

  Future<void> _openReleasePage() async {
    // openReleasePage falls back to the releases page when the link is null.
    await githubUpdater.openReleasePage(
        _result ?? UpdateCheckResult.noReleases());
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final res = _result;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Primary action.
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _busy ? null : _check,
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.system_update_alt_rounded),
            label: Text(
              _installing
                  ? 'Скачиваем и открываем установщик…'
                  : _checking
                      ? 'Ищем новый релиз…'
                      : res == null
                          ? 'Проверить и обновить'
                          : 'Проверить снова',
            ),
          ),
        ),
        const SizedBox(height: 12),
        _buildResult(scheme, res),
        const SizedBox(height: 8),
        Center(
          child: TextButton.icon(
            onPressed: _busy ? null : _openReleasePage,
            icon: const Icon(Icons.open_in_new_rounded, size: 16),
            label: const Text('Открыть GitHub Releases'),
            style: TextButton.styleFrom(
              textStyle: const TextStyle(fontSize: 12.5),
              foregroundColor: scheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildResult(ColorScheme scheme, UpdateCheckResult? res) {
    if (res == null) {
      return const _ResultCard(
        icon: Icons.cloud_queue_rounded,
        title: 'Обновления из GitHub',
        lines: [
          'Одно нажатие проверит GitHub, скачает новый APK и откроет установщик',
        ],
      );
    }
    final asset = res.asset;
    final date =
        res.publishedAt != null ? res.publishedAt!.split('T').first : null;

    switch (res.kind) {
      case UpdateKind.error:
        return _ResultCard(
          icon: Icons.error_outline_rounded,
          tone: scheme.error,
          title: 'Не удалось проверить',
          lines: [res.error ?? 'Неизвестная ошибка'],
        );
      case UpdateKind.none:
        return const _ResultCard(
          icon: Icons.info_outline_rounded,
          title: 'Нет доступных релизов',
          lines: [
            'GitHub пока не вернул опубликованный релиз Mide',
          ],
        );
      case UpdateKind.noMatch:
        return _ResultCard(
          icon: Icons.search_off_rounded,
          title: 'Версия ${res.latestVersion} найдена',
          lines: [
            currentPlatformTag == 'android'
                ? 'В релизе нет совместимого APK для Android arm64'
                : 'Автоустановка сейчас доступна только в Android arm64-сборке',
          ],
        );
      case UpdateKind.upToDate:
        return _ResultCard(
          icon: Icons.check_circle_rounded,
          tone: scheme.primary,
          title: 'Установлена последняя версия',
          lines: [res.latestVersion ?? ''],
        );
      case UpdateKind.update:
        return _ResultCard(
          icon: Icons.cloud_download_rounded,
          tone: scheme.primary,
          title: _installing
              ? 'Скачиваем версию ${res.latestVersion}'
              : 'Доступна версия ${res.latestVersion}',
          lines: [
            if (asset != null) '${asset.name} · ${asset.sizeMb}',
            if (date != null) 'Выпущена: $date',
            if (res.notes != null && res.notes!.isNotEmpty) res.notes!,
            if (_installing)
              'После загрузки Android запросит подтверждение установки.',
          ],
        );
      case UpdateKind.installerOpened:
        return _ResultCard(
          icon: Icons.system_update_alt_rounded,
          tone: scheme.primary,
          title: 'Обновление передано Android: ${res.latestVersion}',
          lines: [
            'Файл: ${asset?.name ?? '—'}',
            'Подтверди установку в системном окне. Если Android попросит разрешение, разреши установку для Mide.',
          ],
        );
    }
  }
}

/// A rounded result card under the update button: icon + title + detail
/// lines, with an optional accent and action row (e.g. the install button).
class _ResultCard extends StatelessWidget {
  const _ResultCard({
    required this.icon,
    required this.title,
    required this.lines,
    this.tone,
    this.actions = const [],
  });

  final IconData icon;
  final String title;
  final List<String> lines;
  final Color? tone;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = tone ?? scheme.onSurfaceVariant;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: tone != null
              ? tone!.withValues(alpha: 0.35)
              : scheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: accent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: scheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
          if (lines.isNotEmpty) ...[
            const SizedBox(height: 6),
            ...lines.map(
              (l) => Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  l,
                  style:
                      TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
                ),
              ),
            ),
          ],
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 12),
            ...actions,
          ],
        ],
      ),
    );
  }
}
