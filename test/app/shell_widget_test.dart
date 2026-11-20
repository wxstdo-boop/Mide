// Widget tests for the shell chrome: launch splash hand-off, the pill
// navigation (pressed feedback + switching) and the Settings update section.
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mide/core/nav/app_tab_provider.dart';
import 'package:mide/features/updater/update_service.dart';
import 'package:mide/features/updater/updater_types.dart';
import 'package:mide/main.dart';

/// Pumps the app and lets the launch splash finish so tests start on the shell.
Future<void> pumpApp(WidgetTester tester) async {
  await tester.pumpWidget(const ProviderScope(child: MideApp()));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 1800));
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

    testWidgets('eases out instead of cutting to the shell', (tester) async {
      await tester.pumpWidget(const ProviderScope(child: MideApp()));
      await tester.pump();

      // The overlay's own FadeTransition is the outermost one; sample it
      // across the exit window and require a gradual, monotonic fade. A hard
      // cut would show up as the same value twice and then gone.
      // The exit fade wraps the splash's whole overlay Stack. Selecting it by
      // that structure is unambiguous; the emblem has its own inner fade that
      // holds at 1.0 throughout the exit, so index-based pickers made this
      // test pass no matter what.
      double overlayOpacity() => tester
          .widget<FadeTransition>(
            find.byWidgetPredicate(
              (w) => w is FadeTransition && w.child is Stack,
            ),
          )
          .opacity
          .value;

      // Hold phase: the splash must be fully opaque, not half-transparent.
      // The backdrop holds to 72% of the 1700ms timeline (1224ms), so 900ms is
      // safely inside it.
      await tester.pump(const Duration(milliseconds: 900));
      expect(overlayOpacity(), closeTo(1.0, 0.001));

      final samples = <double>[];
      // Sample inside the exit window (1224ms → 1700ms); overshooting it would
      // find the overlay already removed from the tree.
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 70));
        samples.add(overlayOpacity());
      }

      // Strictly non-increasing: the splash never pops back to visible.
      for (var i = 1; i < samples.length; i++) {
        expect(
          samples[i],
          lessThanOrEqualTo(samples[i - 1] + 1e-6),
          reason: 'opacity went back up at sample $i: $samples',
        );
      }
      // And it actually moved: several distinct intermediate values prove the
      // fade is animated rather than a single-frame swap.
      final distinct = samples.toSet();
      expect(
        distinct.length,
        greaterThan(2),
        reason: 'expected a glide, got $samples',
      );
      expect(samples.last, lessThan(0.9));

      // Once the timeline ends the overlay leaves the tree entirely.
      await tester.pump(const Duration(milliseconds: 1200));
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

    testWidgets('the wordmark is terminated by a crimson dot', (tester) async {
      await pumpApp(tester);

      // The dot is a plain Container drawn next to the header wordmark, so find
      // it by the shape it is given rather than by a (private) widget type.
      final dots = tester
          .widgetList<Container>(find.byType(Container))
          .where((c) {
            final d = c.decoration;
            return d is BoxDecoration && d.shape == BoxShape.circle;
          })
          .where((c) => c.constraints?.maxWidth != null)
          .toList();
      expect(dots, isNotEmpty, reason: 'header should end with a brand dot');

      final dot = dots.firstWhere((c) {
        final d = c.decoration! as BoxDecoration;
        return d.color != null && d.boxShadow != null;
      });
      final decoration = dot.decoration! as BoxDecoration;
      expect(decoration.shape, BoxShape.circle);
      // Brand red, not the neutral onSurface ink of the wordmark itself.
      expect(decoration.color, isNotNull);
      expect(
        decoration.color!.r,
        greaterThan(decoration.color!.b),
        reason: 'the dot must be red-dominant, got ${decoration.color}',
      );
    });

    testWidgets('only the product name gets the brand dot', (tester) async {
      int brandDots() =>
          tester.widgetList<Container>(find.byType(Container)).where((c) {
            final d = c.decoration;
            return d is BoxDecoration &&
                d.shape == BoxShape.circle &&
                d.boxShadow != null;
          }).length;

      await pumpApp(tester);
      expect(brandDots(), 1, reason: 'the NPV header shows "MIDE."');

      // "MEarn" is a section title, not the product name.
      await tester.tap(find.text('Earn'));
      // Let the tab switcher finish: until it does, the outgoing NPV header is
      // still mounted and would be counted.
      await tester.pumpAndSettle();
      expect(brandDots(), 0, reason: 'section headers carry no brand dot');
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

      await tester.tap(find.text('CRY'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));

      expect(activeTab(tester), 0);
      expect(find.text('Ada Cry (Ада Край)'), findsOneWidget);
    });

    testWidgets('3D and Clip open from the VPN header and come back', (
      tester,
    ) async {
      await pumpApp(tester);
      expect(activeTab(tester), 1);

      await tester.tap(find.byIcon(Icons.view_in_ar_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Мира'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.arrow_back_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Мира'), findsNothing);

      await tester.tap(find.byIcon(Icons.video_settings_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Clip Studio'), findsOneWidget);
    });

    testWidgets('pressing a pill shows crimson feedback without switching', (
      tester,
    ) async {
      await pumpApp(tester);
      final before = activeTab(tester);

      // Hold the finger down: the tab must not switch until release, but the
      // crimson highlight has to be painted.
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Earn')),
      );
      await tester.pump(const Duration(milliseconds: 120));

      final ink = tester.widget<InkWell>(
        find.ancestor(of: find.text('Earn'), matching: find.byType(InkWell)),
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
      expect(activeTab(tester), 2);
    });

    testWidgets('rapid taps settle on the last pill', (tester) async {
      await pumpApp(tester);

      for (final label in ['CRY', 'Earn', 'NPV', 'CRY']) {
        await tester.tap(find.text(label));
        await tester.pump(const Duration(milliseconds: 90));
      }
      await tester.pump(const Duration(milliseconds: 900));

      expect(activeTab(tester), 0);
      expect(find.text('Ada Cry (Ада Край)'), findsOneWidget);
    });
  });

  group('settings update section', () {
    Widget host(FakeUpdateService service) => ProviderScope(
      overrides: [updateServiceProvider.overrideWithValue(service)],
      child: const MaterialApp(home: Scaffold(body: SettingsPage())),
    );

    testWidgets('checks on its own, with no update button', (tester) async {
      final service = FakeUpdateService(
        result: UpdateCheckResult.upToDate(latestVersion: '1.0.6'),
      );
      await tester.pumpWidget(host(service));
      await tester.pumpAndSettle();

      // The check is what opening Settings does, so no action is required.
      expect(service.checks, 1);
      expect(find.text('Установлена последняя версия'), findsOneWidget);
      expect(find.text('Проверить и обновить'), findsNothing);
      expect(find.text('Проверить снова'), findsNothing);
      expect(find.text('Открыть GitHub Releases'), findsOneWidget);
    });

    testWidgets('downloads and installs by itself when an update exists', (
      tester,
    ) async {
      final service = FakeUpdateService(
        result: UpdateCheckResult.updateAvailable(
          latestVersion: '1.0.7',
          asset: const UpdateAsset(
            name: 'mide-1.0.7-arm64-release.apk',
            url: 'https://github.com/wxstdo-boop/Mide/releases/download/v.apk',
            sizeBytes: 1024,
          ),
        ),
      );
      await tester.pumpWidget(host(service));
      await tester.pumpAndSettle();

      expect(service.checks, 1);
      expect(service.installs, 1, reason: 'no button to press');
      expect(
        find.textContaining('Обновление передано Android'),
        findsOneWidget,
      );
    });

    testWidgets('shows the reason when the check fails', (tester) async {
      final service = FakeUpdateService(
        result: UpdateCheckResult.failure('Нет соединения с GitHub'),
      );
      await tester.pumpWidget(host(service));
      await tester.pumpAndSettle();

      expect(find.text('Не удалось проверить'), findsOneWidget);
      expect(find.text('Нет соединения с GitHub'), findsOneWidget);
    });

    testWidgets('a thrown error becomes a readable card, not a crash', (
      tester,
    ) async {
      final service = FakeUpdateService(throwOnCheck: true);
      await tester.pumpWidget(host(service));
      await tester.pumpAndSettle();

      expect(find.text('Не удалось проверить'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

class FakeUpdateService implements UpdateService {
  FakeUpdateService({this.result, this.throwOnCheck = false});

  final UpdateCheckResult? result;
  final bool throwOnCheck;

  int checks = 0;
  int installs = 0;
  int releasesOpened = 0;

  @override
  Future<UpdateCheckResult> checkLatest() async {
    checks++;
    if (throwOnCheck) throw StateError('network down');
    return result ?? UpdateCheckResult.noReleases();
  }

  @override
  Future<UpdateCheckResult> downloadAndInstall(
    UpdateCheckResult source, {
    void Function(double? progress)? onProgress,
  }) async {
    installs++;
    onProgress?.call(1);
    return UpdateCheckResult.installerOpened(source, '/tmp/fake.apk');
  }

  @override
  Future<void> openReleasePage(UpdateCheckResult result) async {
    releasesOpened++;
  }
}
