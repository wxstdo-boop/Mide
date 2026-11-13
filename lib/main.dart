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

part 'app/shell.dart';
part 'app/tabs/vpn_tab.dart';
part 'app/tabs/mearn_tab.dart';
part 'app/pages/settings_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Portrait only - no auto-rotation.
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
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
      if (s == AnimationStatus.completed && mounted) {
        setState(() => _gone = true);
      }
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
        Color.alphaBlend(
            scheme.primary.withValues(alpha: 0.18), scheme.surface),
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
                  position: Tween<Offset>(
                          begin: const Offset(0.0, 0.03), end: Offset.zero)
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
