// Persisted-state migration: the shell lost two tabs and the theme gained a
// "follow the system" option, so values saved by older builds must still
// resolve to something sensible instead of a blank screen.
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mide/core/nav/app_tab_provider.dart';
import 'package:mide/core/theme/theme_providers.dart';

void main() {
  group('AppTabNotifier', () {
    test('exposes three tabs', () {
      expect(AppTabNotifier.tabCount, 3);
    });

    test('keeps the persisted value when it still exists', () {
      expect(AppTabNotifier(seed: 0).build(), 0);
      expect(AppTabNotifier(seed: 2).build(), 2);
    });

    test('falls back to NPV for the retired 3D and Clip tabs', () {
      // These were tabs 3 and 4 before 3D and Clip moved into the VPN header.
      expect(AppTabNotifier(seed: 3).build(), 1);
      expect(AppTabNotifier(seed: 4).build(), 1);
      expect(AppTabNotifier(seed: 99).build(), 1);
      expect(AppTabNotifier(seed: -1).build(), 1);
    });
  });

  group('MideThemeChoice', () {
    test('offers light, dark and system', () {
      expect(MideThemeChoice.values.length, 3);
      expect(MideThemeChoice.system.mode, ThemeMode.system);
      expect(MideThemeChoice.light.mode, ThemeMode.light);
      expect(MideThemeChoice.dark.mode, ThemeMode.dark);
    });

    test('loads the pre-system names so an update keeps the palette', () {
      expect(MideThemeChoice.fromName('lightBloody'), MideThemeChoice.light);
      expect(MideThemeChoice.fromName('darkBloody'), MideThemeChoice.dark);
      expect(MideThemeChoice.fromName('system'), MideThemeChoice.system);
      expect(MideThemeChoice.fromName('nonsense'), isNull);
    });

    test('system previews whatever the platform is showing', () {
      expect(
        MideThemeChoice.system.previewBrightness(Brightness.dark),
        Brightness.dark,
      );
      expect(
        MideThemeChoice.system.previewBrightness(Brightness.light),
        Brightness.light,
      );
      // Fixed choices ignore the platform.
      expect(
        MideThemeChoice.light.previewBrightness(Brightness.dark),
        Brightness.light,
      );
    });
  });
}
