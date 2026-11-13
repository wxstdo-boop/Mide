// Mide theme — Material You (Material Design 3), driven by dynamic colors.
import 'package:material_ui/material_ui.dart';

/// App-specific semantic colors layered on top of the dynamic [ColorScheme].
@immutable
class MideTheme extends ThemeExtension<MideTheme> {
  /// Positive / connected state color.
  final Color success;
  final Color successContainer;
  final Color onSuccessContainer;

  const MideTheme({
    required this.success,
    required this.successContainer,
    required this.onSuccessContainer,
  });

  @override
  MideTheme copyWith({
    Color? success,
    Color? successContainer,
    Color? onSuccessContainer,
  }) {
    return MideTheme(
      success: success ?? this.success,
      successContainer: successContainer ?? this.successContainer,
      onSuccessContainer: onSuccessContainer ?? this.onSuccessContainer,
    );
  }

  @override
  MideTheme lerp(MideTheme? other, double t) {
    if (other is! MideTheme) return this;
    return MideTheme(
      success: Color.lerp(success, other.success, t)!,
      successContainer: Color.lerp(successContainer, other.successContainer, t)!,
      onSuccessContainer: Color.lerp(onSuccessContainer, other.onSuccessContainer, t)!,
    );
  }
}

/// Access app colors from any context: `context.mideTheme.success`.
extension MideThemeX on BuildContext {
  MideTheme get mideTheme => Theme.of(this).extension<MideTheme>()!;
}

/// Seed for the "bloody" themes — deep crimson.
const Color bloodySeed = Color(0xFFC62828);

/// Bloody theme: Material 3 palette seeded with deep crimson, light or dark.
ThemeData buildBloodyTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(seedColor: bloodySeed, brightness: brightness);
  return buildAppTheme(light: scheme, dark: scheme, brightness: brightness);
}

/// Material 3 theme built from the dynamic (wallpaper-derived) color schemes.
///
/// [light] and [dark] come from [DynamicColorBuilder] when available and fall
/// back to a seed-based scheme otherwise, so the app always feels "Material You".
ThemeData buildAppTheme({
  required ColorScheme light,
  required ColorScheme dark,
  required Brightness brightness,
}) {
  final scheme = brightness == Brightness.dark ? dark : light;
  final isDark = brightness == Brightness.dark;

  final success = isDark ? const Color(0xFF3DDC84) : const Color(0xFF0F7B3F);
  final successContainer = isDark ? const Color(0xFF0E4A27) : const Color(0xFFB7F0CB);
  final onSuccessContainer = isDark ? const Color(0xFFC2F3D3) : const Color(0xFF043011);

  const radius = 16.0;

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    splashFactory: InkRipple.splashFactory,

    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: scheme.onSurface,
        fontSize: 22,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.3,
      ),
    ),

    cardTheme: CardThemeData(
      color: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
    ),

    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 48),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),

    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),

    tooltipTheme: TooltipThemeData(
      // Follow the active theme instead of M3's "inverse" surface, which
      // intentionally looks like the *other* theme (dark tooltip on the light
      // theme, light tooltip on the dark one). surfaceContainerHighest gives a
      // light chip on light theme and a dark chip on dark theme.
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      textStyle: TextStyle(
        color: scheme.onSurface,
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      waitDuration: const Duration(milliseconds: 350),
      showDuration: const Duration(milliseconds: 1800),
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radius),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radius),
        borderSide: BorderSide(color: scheme.primary, width: 2),
      ),
      labelStyle: TextStyle(color: scheme.onSurfaceVariant),
    ),

    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),

    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: scheme.primary,
      linearTrackColor: scheme.surfaceContainerHighest,
    ),

    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant,
      thickness: 1,
      space: 1,
    ),

    floatingActionButtonTheme: FloatingActionButtonThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      elevation: 2,
    ),

    extensions: [
      MideTheme(
        success: success,
        successContainer: successContainer,
        onSuccessContainer: onSuccessContainer,
      ),
    ],
  );
}
