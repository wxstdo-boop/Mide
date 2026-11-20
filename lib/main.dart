// Mide — FOSS VPN client. Material You (M3) interface with "bloody" themes.
import 'dart:async';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'core/nav/app_tab_provider.dart';
import 'core/theme/mide_theme.dart';
import 'core/theme/theme_providers.dart';
import 'features/ai/ai_chat_ui.dart';
import 'features/ai/ai_model.dart';
import 'features/ai/ai_providers.dart';
import 'features/clip/clip_export.dart';
import 'features/clip/clip_models.dart';
import 'features/clip/clip_providers.dart';
import 'features/clip/preview/clip_player.dart';
import 'features/vpn/providers/vpn_providers.dart';
import 'features/updater/github_config.dart';
import 'features/updater/update_service.dart';
import 'features/updater/updater_types.dart';
import 'features/vpn/vpn_settings.dart';

part 'app/shell.dart';
part 'app/tabs/vpn_tab.dart';
part 'app/tabs/mearn_tab.dart';
part 'app/tabs/companion_tab.dart';
part 'app/tabs/clip_studio_tab.dart';
part 'app/pages/settings_page.dart';

/// Version shown in the tab headers. Sourced from the same value the updater
/// compares against, so the chip can never drift from the real build.
String get appVersionLabel => GithubConfig.currentVersion;

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
        appTabProvider.overrideWith(() => AppTabNotifier(seed: seededTab)),
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
      const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics());
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
      themeMode: choice.mode,
      // Short enough to feel like a response, long enough to read as a fade.
      // 500ms lagged visibly behind the settings carousel, which is what made
      // switching themes look like a mess.
      themeAnimationDuration: const Duration(milliseconds: 280),
      themeAnimationCurve: Curves.easeOut,
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
    // 1.7s total. The phases below are authored as fractions of this single
    // linear timeline; each one carries its own curve, so nothing warps another
    // phase (see the note on `emblemOpacity`).
    duration: const Duration(milliseconds: 1700),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Opaque backdrop mirroring res/drawable/launch_background.xml stop for
    // stop, so the cold-start window, this overlay and the app are one
    // continuous surface. Deriving it from the scheme instead left the native
    // window at #FDE3E0 against a #EBD9D7 Flutter splash — a visible step on
    // every launch.
    final background = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: isDark
          ? const [Color(0xFF3A2022), Color(0xFF241B1C), Color(0xFF1E1718)]
          : const [Color(0xFFFDE3E0), Color(0xFFFFF2F0), Color(0xFFFFF8F6)],
      stops: const [0.0, 0.5, 1.0],
    );

    // Timeline: fade in 0–26%, hold to 56%, wordmark leaves 56–72%, backdrop
    // lifts 70–100%.
    //
    // Every phase is its own `TweenSequenceItem` with a chained `CurveTween`
    // on a *linear* controller. Wrapping the whole sequence in one
    // `CurvedAnimation` warped the timeline instead of shaping each phase: the
    // "hold" really ended at ~56% of the wall clock, so the backdrop was
    // already 16% transparent while the wordmark was still drawn at full
    // strength and the app's content bled through as a grey band directly under
    // "MIDE" — the reported underline.
    // NOTE: `TweenSequence` normalises its weights to *their own sum*, not to
    // the controller range. A sequence whose weights total 72 therefore spreads
    // over the whole timeline and silently stretches the last phase to the end —
    // which is exactly how the wordmark ended up still drawn while the backdrop
    // was already lifting. Every sequence below totals 100 and ends with an
    // explicit constant, so its phases land on the fractions named above.
    final emblemOpacity = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.0, end: 1.0)
            .chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 26,
      ),
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 30),
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 0.0)
            .chain(CurveTween(curve: Curves.easeInCubic)),
        weight: 16,
      ),
      TweenSequenceItem(tween: ConstantTween(0.0), weight: 28),
    ]).animate(_c);

    // Settles at exactly 1.0 and stays there for the whole hold. Scaling the
    // emblem through a constant 0.92 resampled the rasterised subtree for the
    // full 1s, which is what made the glyph look soft; at 1.0 it is drawn
    // pixel-exact.
    final scale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.94, end: 1.0)
            .chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 26,
      ),
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 30),
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 1.03)
            .chain(CurveTween(curve: Curves.easeInCubic)),
        weight: 16,
      ),
      TweenSequenceItem(tween: ConstantTween(1.03), weight: 28),
    ]).animate(_c);

    // A short upward drift while the wordmark fades. Translation only — it does
    // not resample the emblem, so the glyph stays sharp to the last frame.
    final lift = TweenSequence<double>([
      TweenSequenceItem(tween: ConstantTween(0.0), weight: 26),
      TweenSequenceItem(tween: ConstantTween(0.0), weight: 30),
      TweenSequenceItem(
        tween: Tween(begin: 0.0, end: -14.0)
            .chain(CurveTween(curve: Curves.easeInCubic)),
        weight: 16,
      ),
      TweenSequenceItem(tween: ConstantTween(-14.0), weight: 28),
    ]).animate(_c);

    // The backdrop holds full opacity until the wordmark is completely gone,
    // then lifts over the last 30% (~510ms) with an ease-in-out tail, so the
    // app is revealed by a long, even fade instead of a hard step.
    final exit = TweenSequence<double>([
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 72),
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 0.0)
            .chain(CurveTween(curve: Curves.easeInOutCubic)),
        weight: 28,
      ),
    ]).animate(_c);

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
                      // Must match the gradient's last stop exactly, or the
                      // window strips behind the system bars (which the gradient
                      // does not reach) show a seam.
                      color: background.colors.last,
                      child: DecoratedBox(
                        decoration: BoxDecoration(gradient: background),
                      ),
                    ),
                    Center(
                      child: FadeTransition(
                        opacity: emblemOpacity,
                        // Scale and lift are applied to the emblem alone —
                        // never to the backdrop, or the edges would expose the
                        // app. Driven by AnimatedBuilder: reading `scale.value`
                        // straight in build left the emblem frozen, so the exit
                        // looked like a hard jump instead of a glide.
                        child: AnimatedBuilder(
                          animation: _c,
                          builder: (context, child) => Transform.translate(
                            offset: Offset(0, lift.value),
                            child: Transform.scale(
                              scale: scale.value,
                              child: child,
                            ),
                          ),
                          child: const _SplashEmblem(),
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
  const _SplashEmblem();

  /// Edge of the squircle chip.
  static const double _size = 152;

  /// Same squircle radius as the launcher icon, so the splash emblem and the
  /// installed app icon are the same silhouette.
  static const double _radius = _size * 0.30;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
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
                child: Padding(
                  padding: const EdgeInsets.all(_size * 0.155),
                  // The asset's alpha bbox is centred vertically, but its ink
                  // sits 57.5/1024 to the right of the canvas centre — the glyph
                  // visibly leaned right inside an otherwise centred chip.
                  // The fraction is relative to the *image* box (the padded
                  // area), so it has to be applied inside the padding; applying
                  // it to the chip box overshot and pushed the glyph 9px left.
                  child: FractionalTranslation(
                    translation: const Offset(-57.5 / 1024, 0),
                    child: Image.asset(
                      'assets/icon/mide_mark.png',
                      fit: BoxFit.contain,
                      // A smooth vector-like shape drawn at 152dp from a 1024px
                      // source; the default `medium` filter left the drop's edge
                      // visibly soft.
                      filterQuality: FilterQuality.high,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        // 32dp clears the chip's blurred drop shadow (12dp offset + 12dp blur
        // reach) so the glow never bleeds into the wordmark.
        const SizedBox(height: 30),
        // Big wordmark: the product name is the splash's focal point, so it is
        // set large, wide-tracked and with a soft crimson glow instead of a
        // small caption. The full stop after it is drawn as its own widget so
        // it keeps the brand red instead of inheriting the wordmark's gradient.
        Row(
          mainAxisSize: MainAxisSize.min,
          // `.end` rather than a baseline alignment: the ShaderMask and the dot
          // both report no text baseline, so `baseline` would silently fall back
          // to box heights. With `height: 1.0` the text box bottom *is* the
          // baseline, so bottom alignment lands the dot where it belongs.
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            ShaderMask(
              blendMode: BlendMode.srcIn,
              shaderCallback: (bounds) => LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  scheme.onSurface,
                  Color.alphaBlend(
                    scheme.primary.withValues(alpha: 0.85),
                    scheme.onSurface,
                  ),
                ],
              ).createShader(bounds),
              child: Text(
                'MIDE',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 46,
                  height: 1.0,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 12,
                  color: Colors.white,
                  shadows: [
                    Shadow(
                      color: scheme.primary.withValues(alpha: 0.45),
                      blurRadius: 24,
                    ),
                  ],
                ),
              ),
            ),
            // `letterSpacing` is applied after the last glyph too, so the run
            // already ends 12px past the E; pull the dot back to sit ~4px off
            // it instead of a letter-gap away.
            Transform.translate(
              offset: const Offset(-8, -2),
              child: const _WordmarkDot(size: 46),
            ),
          ],
        ),
      ],
    );
  }
}

/// The brand's full stop: a crimson dot that terminates the "MIDE" wordmark.
///
/// Sized off the font it follows so the dot stays proportional on the 46pt
/// splash wordmark and the 30pt app header, and drawn as a shape rather than a
/// `.` glyph so it never picks up the surrounding text's gradient, letter
/// spacing or baseline quirks.
class _WordmarkDot extends StatelessWidget {
  const _WordmarkDot({this.size = 46});

  /// Font size of the wordmark the dot terminates.
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final d = size * 0.17;
    return Container(
      width: d,
      height: d,
      // Nudged down so the dot sits on the baseline of the capital letters
      // rather than floating at their optical middle.
      margin: EdgeInsets.only(bottom: size * 0.06),
      decoration: BoxDecoration(
        color: scheme.primary,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: scheme.primary.withValues(alpha: 0.55),
            blurRadius: size * 0.22,
          ),
        ],
      ),
    );
  }
}

/// Shell with the bottom pill navigation: CRY (AI), NPV (VPN), MEarn (crypto).
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
    // swiped, rapid CRY↔NPV↔MEarn tapping can no longer make the panels
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
        // A short cross-fade only: the previous panel used to fade *and*
        // slide *and* scale for 420ms, which repainted the whole screen three
        // times over and read as lag on a mid-range phone. Each panel is its
        // own repaint boundary so the fade cannot dirty the gradient behind.
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          transitionBuilder: (child, animation) =>
              FadeTransition(opacity: animation, child: child),
          layoutBuilder: (currentChild, previousChildren) => Stack(
            fit: StackFit.passthrough,
            alignment: Alignment.topLeft,
            children: [
              ...previousChildren,
              if (currentChild != null) currentChild,
            ],
          ),
          child: RepaintBoundary(
            key: ValueKey(tab),
            child: switch (tab) {
              0 => const AiTab(),
              1 => const VpnTab(),
              _ => const MEarnTab(),
            },
          ),
        ),
      ),
      bottomNavigationBar: const _TabPillBar(),
    );
  }
}
