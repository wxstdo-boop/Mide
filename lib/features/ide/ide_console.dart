// PC-only IDE — bottom console panel (run current file, stream output).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ide_providers.dart';

/// Bottom console: run/stop/clear controls + monospace output log.
class IdeConsolePanel extends ConsumerStatefulWidget {
  const IdeConsolePanel({super.key});

  @override
  ConsumerState<IdeConsolePanel> createState() => _IdeConsolePanelState();
}

class _IdeConsolePanelState extends ConsumerState<IdeConsolePanel> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _autoScroll() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cs = ref.watch(ideConsoleProvider);
    // Re-scroll whenever a line lands.
    ref.listen(ideConsoleProvider, (prev, next) {
      if (next.lines.length != (prev?.lines.length ?? 0)) _autoScroll();
    });

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border(top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Console header ──
          SizedBox(
            height: 38,
            child: Row(
              children: [
                const SizedBox(width: 12),
                Icon(Icons.terminal_rounded, size: 15, color: scheme.primary),
                const SizedBox(width: 6),
                Text(
                  'Консоль',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: scheme.onSurface,
                  ),
                ),
                if (cs.running) ...[
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 2, color: scheme.primary),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'выполняется…',
                    style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                  ),
                ],
                const Spacer(),
                TextButton.icon(
                  onPressed: cs.running
                      ? null
                      : () {
                          final path = ref.read(ideTabsProvider).activeTab?.path;
                          if (path != null) {
                            ref.read(ideConsoleProvider.notifier).run(path);
                          }
                        },
                  icon: const Icon(Icons.play_arrow_rounded, size: 17),
                  label: const Text('Запустить'),
                  style: TextButton.styleFrom(
                    foregroundColor: scheme.primary,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                TextButton.icon(
                  onPressed: cs.running
                      ? () => ref.read(ideConsoleProvider.notifier).stop()
                      : null,
                  icon: const Icon(Icons.stop_rounded, size: 16),
                  label: const Text('Стоп'),
                  style: TextButton.styleFrom(
                    foregroundColor: scheme.error,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                IconButton(
                  tooltip: 'Очистить',
                  onPressed: cs.lines.isEmpty
                      ? null
                      : () => ref.read(ideConsoleProvider.notifier).clear(),
                  icon: const Icon(Icons.delete_sweep_rounded, size: 17),
                  visualDensity: VisualDensity.compact,
                ),
                const SizedBox(width: 6),
              ],
            ),
          ),
          const Divider(height: 1),
          // ── Output log ──
          Expanded(
            child: cs.lines.isEmpty
                ? Center(
                    child: Text(
                      'F5 или ▶ Запустить — вывод появится здесь',
                      style: TextStyle(fontSize: 12, color: scheme.outline),
                    ),
                  )
                : LayoutBuilder(
                    builder: (context, box) => SingleChildScrollView(
                      controller: _scroll,
                      child: Container(
                        width: box.maxWidth,
                        padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
                        child: SelectableText.rich(
                          TextSpan(
                            children: [
                              for (final line in cs.lines)
                                TextSpan(
                                  text: '$line\n',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    height: 1.45,
                                    fontFamilyFallback: const [
                                      'Consolas',
                                      'DejaVu Sans Mono',
                                      'monospace',
                                    ],
                                    color: line.startsWith('[')
                                        ? (line.contains('❌') ||
                                                line.contains('код 1')
                                            ? scheme.error
                                            : scheme.tertiary)
                                        : scheme.onSurfaceVariant,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}


