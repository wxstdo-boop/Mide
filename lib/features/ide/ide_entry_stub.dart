// IDE entry — web/mobile stub (no dart:io, no IDE screen).
// Conditional export partner of ide_entry_io.dart (see ide_entry.dart).
import 'package:flutter/widgets.dart';

/// Invisible placeholder so the AI section can embed the pill unconditionally;
/// the real pill only exists on desktop (PC) builds.
class IdeEntryPill extends StatelessWidget {
  const IdeEntryPill({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
