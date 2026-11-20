// Widget tests for the shell chrome: launch splash hand-off, the pill
// navigation (pressed feedback + switching) and the Settings update section.
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mide/core/nav/app_tab_provider.dart';
import 'package:mide/main.dart';

/// Pumps the app and lets the launch splash finish so tests start on the shell.
Future<void> pumpApp(WidgetTester tester) async {
  await tester.pumpWidget(const ProviderScope(child: MideApp()));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 2900));
  await tester.pumpAndSettle();
}

int activeTab(WidgetTester tester) {
  final container = ProviderScope.containerOf(
    tester.element(find.byType(HomePage)),
  );
  return container.read(appTabProvider);
}

void main() {
  group('launch splash', () {
    testWidgets('shows the MIDE emblem, then lifts off the tree', (
      tester,
    ) async {
      await tester.pumpWidget(const ProviderScope(child: MideApp()));
      await tester.pump();

      // Mid-splash the emblem wordmark is already up.
      await tester.pump(const Duration(milliseconds: 900));
      expect(find.text('MIDE'), findsWidgets);

      // Once the timeline completes the overlay removes itself and the pill
      // bar becomes interactive again.
      await tester.pump(const Duration(milliseconds: 2000));
      await tester.pumpAndSettle();
      expect(find.text('NPV'), findsOneWidget);
    });

    testWidgets('hands off to a usable shell, not a frozen frame', (
      tester,
    ) async {
      await pumpApp(tester);
      // Tapping through the overlay only works if the splash really left.
      await tester.tap(find.text('Earn'));
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.text('Kryptex'), findsOneWidget);
    });
  });

  group('header branding', () {
    testWidgets('MIDE is large, heavy and free of a yellow underline', (
      tester,
    ) async {
      await pumpApp(tester);

      // _AppHeader is private to the main.dart library, so pick the wordmark
      // out by its typography instead of by widget type.
      final titles = tester
          .widgetList<Text>(find.text('MIDE'))
          .where((t) => (t.style?.fontSize ?? 0) >= 28)
          .toList();
      expect(titles, isNotEmpty, reason: 'header MIDE should be huge');

      final title = titles.first;
      expect(title.style!.fontWeight, FontWeight.w900);
      // No decoration at all: the old header drew a yellow bar under the
      // name, which is what the "no yellow underline" report was about.
      expect(title.style!.decoration, isNull);
      expect(title.style!.decorationColor, isNull);

      // And the retired persona names are gone from the header.
      expect(find.text('Ада'), findsNothing);
      expect(find.text('АДУСЯ'), findsNothing);
      expect(find.text('M.AI'), findsNothing);
    });
  });

  group('narrow screen', () {
    testWidgets('huge MIDE title never overflows a narrow phone', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(280, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await pumpApp(tester);

      // A RenderFlex overflow would have been thrown during layout.
      expect(tester.takeException(), isNull);
      expect(find.text('MIDE'), findsWidgets);
    });
  });

  group('pill navigation', () {
    testWidgets('selects a pill on tap', (tester) async {
      await pumpApp(tester);
      expect(activeTab(tester), 1); // NPV by default

      await tester.tap(find.text('3D'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));

      expect(activeTab(tester), 3);
      expect(find.text('Мира'), findsOneWidget);
    });

    testWidgets('pressing a pill shows crimson feedback without switching', (
      tester,
    ) async {
      await pumpApp(tester);
      final before = activeTab(tester);

      // Hold the finger down: the tab must not switch until release, but the
      // crimson highlight has to be painted.
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Clip')),
      );
      await tester.pump(const Duration(milliseconds: 120));

      final ink = tester.widget<InkWell>(
        find.ancestor(of: find.text('Clip'), matching: find.byType(InkWell)),
      );
      expect(ink.splashColor, isNotNull);
      expect(ink.highlightColor, isNotNull);
      // Feedback is semi-transparent blood, not an opaque slab.
      expect(ink.highlightColor!.a, greaterThan(0.0));
      expect(ink.highlightColor!.a, lessThan(1.0));
      expect(activeTab(tester), before);

      await gesture.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      expect(activeTab(tester), 4);
    });

    testWidgets('rapid taps settle on the last pill', (tester) async {
      await pumpApp(tester);

      for (final label in ['AGI', 'Earn', '3D', 'Clip']) {
        await tester.tap(find.text(label));
        await tester.pump(const Duration(milliseconds: 90));
      }
      await tester.pump(const Duration(milliseconds: 900));

      expect(activeTab(tester), 4);
      expect(find.text('Clip Studio'), findsOneWidget);
    });
  });

  group('settings update section', () {
    testWidgets('offers a check-and-update action', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: Scaffold(body: SettingsPage())),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Проверить и обновить'), findsOneWidget);
      expect(find.text('Открыть GitHub Releases'), findsOneWidget);
    });
  });
}
