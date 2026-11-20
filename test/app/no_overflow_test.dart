// Guards against layout overflow on narrow phones. The Earn stats row used to
// overflow by 82px at 360dp wide, which clipped a chip; nothing caught it
// because the other widget tests run at the default 800x600 test surface.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mide/core/nav/app_tab_provider.dart';
import 'package:mide/main.dart';

/// Phone widths worth checking: 320 is the narrowest Android still in use,
/// 360 is the most common, 411 is a large phone.
const _widths = <double>[320, 360, 411];

Future<void> _bootAt(WidgetTester tester, double width, int tab) async {
  tester.view.physicalSize = Size(width * 3, 2400);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(const ProviderScope(child: MideApp()));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 1800));
  await tester.pumpAndSettle();

  final container = ProviderScope.containerOf(
    tester.element(find.byType(HomePage)),
  );
  container.read(appTabProvider.notifier).select(tab);
  // The AI tab never settles (shimmer + breathing dot), so pump a fixed
  // window instead of waiting for quiet.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  for (final width in _widths) {
    group('no overflow at ${width.toInt()}dp', () {
      for (final tab in [0, 1, 2]) {
        testWidgets('tab $tab', (tester) async {
          await _bootAt(tester, width, tab);
          expect(
            tester.takeException(),
            isNull,
            reason: 'tab $tab overflowed at ${width.toInt()}dp',
          );
        });
      }

      testWidgets('3D page', (tester) async {
        await _bootAt(tester, width, 1);
        tester
            .state<NavigatorState>(find.byType(Navigator))
            .push(
              MaterialPageRoute<void>(builder: (_) => const CompanionPage()),
            );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump(const Duration(milliseconds: 400));
        expect(
          tester.takeException(),
          isNull,
          reason: '3D page overflowed at ${width.toInt()}dp',
        );
      });

      testWidgets('Clip Studio page', (tester) async {
        await _bootAt(tester, width, 1);
        tester
            .state<NavigatorState>(find.byType(Navigator))
            .push(
              MaterialPageRoute<void>(builder: (_) => const ClipStudioPage()),
            );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump(const Duration(milliseconds: 400));
        expect(
          tester.takeException(),
          isNull,
          reason: 'Clip Studio page overflowed at ${width.toInt()}dp',
        );
      });
    });
  }
}
