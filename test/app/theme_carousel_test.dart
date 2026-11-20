// Guards the theme carousel against the "бардак" bug: the theme used to be
// applied from the PageView builder, so a single animated swipe fired the
// swap on every frame and the UI flickered through palettes. It must now be
// applied exactly once, when the carousel settles.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mide/core/theme/theme_providers.dart';
import 'package:mide/main.dart';

void main() {
  testWidgets('a swipe applies the theme exactly once', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final applied = <MideThemeChoice>[];
    container.listen<MideThemeChoice>(
      themeChoiceProvider,
      (_, next) => applied.add(next),
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: ThemeCarousel())),
      ),
    );
    await tester.pumpAndSettle();

    // The carousel opens on the saved choice (system, the last page), so a
    // leftward drag lands on the previous card.
    final pageWidth = tester.getSize(find.byType(PageView)).width * 0.86;
    await tester.drag(find.byType(PageView), Offset(pageWidth, 0));
    await tester.pumpAndSettle();

    // A frame-by-frame apply would push several entries here.
    expect(
      applied.length,
      lessThanOrEqualTo(1),
      reason: 'theme was applied ${applied.length} times for one swipe',
    );
    expect(container.read(themeChoiceProvider), MideThemeChoice.dark);
  });
}
