// PC-only IDE — tab strip + code editor pane (line numbers, hotkeys).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ide_providers.dart';

/// Horizontal strip of open file tabs with dirty markers and close buttons.
class IdeTabStrip extends ConsumerWidget {
  const IdeTabStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final ts = ref.watch(ideTabsProvider);
    final notifier = ref.read(ideTabsProvider.notifier);

    if (ts.tabs.isEmpty) return const SizedBox.shrink();

    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
        ),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (var i = 0; i < ts.tabs.length; i++)
            _TabChip(
              tab: ts.tabs[i],
              active: i == ts.active,
              onTap: () => notifier.activate(i),
              onClose: () => notifier.close(i),
            ),
        ],
      ),
    );
  }
}

class _TabChip extends StatelessWidget {
  const _TabChip({
    required this.tab,
    required this.active,
    required this.onTap,
    required this.onClose,
  });

  final IdeTab tab;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(0),
      child: Container(
        constraints: const BoxConstraints(minWidth: 110, maxWidth: 220),
        padding: const EdgeInsets.only(left: 14, right: 6),
        decoration: BoxDecoration(
          color: active ? scheme.surfaceContainerHighest : null,
          border: Border(
            right: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
            bottom: BorderSide(
              color: active ? scheme.primary : Colors.transparent,
              width: 2.5,
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              tab.name.endsWith('.dart') ? Icons.terminal_rounded : Icons.insert_drive_file_outlined,
              size: 14,
              color: active ? scheme.primary : scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                tab.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  color: scheme.onSurface,
                ),
              ),
            ),
            const SizedBox(width: 6),
            SizedBox(
              width: 22,
              height: 22,
              child: tab.dirty
                  ? Tooltip(
                      message: 'Не сохранено (Ctrl+S)',
                      child: Icon(Icons.circle, size: 8, color: scheme.tertiary),
                    )
                  : IconButton(
                      tooltip: 'Закрыть',
                      padding: EdgeInsets.zero,
                      iconSize: 14,
                      onPressed: onClose,
                      icon: Icon(Icons.close_rounded, color: scheme.outline),
                    ),
            ),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }
}

// ── Editor pane ────────────────────────────────────────────────────────────

/// Editor: line-number gutter + multiline TextField with IDE hotkeys
/// (Tab inserts spaces, Ctrl+S saves, external content syncs in).
class IdeEditorPane extends ConsumerStatefulWidget {
  const IdeEditorPane({super.key, required this.emptyHint});

  /// Shown when no file is open.
  final Widget emptyHint;

  @override
  ConsumerState<IdeEditorPane> createState() => _IdeEditorPaneState();
}

class _IdeEditorPaneState extends ConsumerState<IdeEditorPane> {
  static const _fontSize = 14.0;
  static const _lineHeight = 1.5;
  static const _gutterWidth = 56.0;

  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  String? _boundPath;
  String _caretInfo = '1:1';

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_updateCaret);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncFromState());
  }

  @override
  void dispose() {
    _scroll.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  void _updateCaret() {
    if (!mounted) return;
    final sel = _ctrl.selection;
    if (!sel.isValid) return;
    final text = _ctrl.text;
    final offset = sel.baseOffset.clamp(0, text.length);
    final before = text.substring(0, offset);
    final line = before.split('\n').length;
    final col = offset - before.lastIndexOf('\n');
    final info = '$line:$col';
    if (info != _caretInfo) setState(() => _caretInfo = info);
  }

  /// Rebinds the controller when the active tab changes and adopts external
  /// buffer changes (AI apply) while the same file stays active.
  void _syncFromState() {
    final tab = ref.read(ideTabsProvider).activeTab;
    if (tab == null) {
      _boundPath = null;
      if (_ctrl.text.isNotEmpty) _ctrl.clear();
      return;
    }
    if (_boundPath != tab.path) {
      _boundPath = tab.path;
      _ctrl.value = TextEditingValue(
        text: tab.content,
        selection: TextSelection.collapsed(offset: tab.content.length),
      );
      _updateCaret();
      return;
    }
    if (_ctrl.text != tab.content) {
      _ctrl.value = TextEditingValue(
        text: tab.content,
        selection: TextSelection.collapsed(offset: tab.content.length),
      );
      _updateCaret();
    }
  }

  void _onChanged(String text) {
    final path = _boundPath;
    if (path == null) return;
    ref.read(ideTabsProvider.notifier).setContent(path, text);
  }

  /// Tab key: insert two spaces at the caret (classic IDE behaviour).
  void _insertTab() {
    final sel = _ctrl.selection;
    final text = _ctrl.text;
    if (!sel.isValid) {
      _ctrl.text = '$text  ';
      _ctrl.selection = TextSelection.collapsed(offset: _ctrl.text.length);
      _onChanged(_ctrl.text);
      return;
    }
    final start = sel.start.clamp(0, text.length);
    final end = sel.end.clamp(0, text.length);
    final next = '${text.substring(0, start)}  ${text.substring(end)}';
    _ctrl.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: start + 2),
    );
    _onChanged(next);
  }

  Future<void> _save() async {
    final err = await ref.read(ideTabsProvider.notifier).save();
    if (err != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ts = ref.watch(ideTabsProvider);
    ref.listen(ideTabsProvider, (prev, next) => _syncFromState());

    final tab = ts.activeTab;
    if (tab == null) return widget.emptyHint;

    final lineCount = _ctrl.text.split('\n').length;
    const linePx = _fontSize * _lineHeight;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.tab): _insertTab,
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): _save,
      },
      child: Focus(
        autofocus: true,
        child: Stack(
          children: [
            // ── Line-number gutter ──
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: _gutterWidth,
              child: Container(
                color: scheme.surfaceContainerLow,
                child: ClipRect(
                  child: AnimatedBuilder(
                    animation: _scroll,
                    builder: (context, _) {
                      final offset = _scroll.hasClients ? _scroll.offset : 0.0;
                      return Transform.translate(
                        offset: Offset(0, -offset),
                        child: Padding(
                          padding: const EdgeInsets.only(top: 10, right: 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              for (var i = 1; i <= lineCount; i++)
                                SizedBox(
                                  height: linePx,
                                  child: Text(
                                    '$i',
                                    style: TextStyle(
                                      fontSize: _fontSize - 1.5,
                                      height: _lineHeight,
                                      fontFamilyFallback: const [
                                        'Consolas',
                                        'DejaVu Sans Mono',
                                        'monospace',
                                      ],
                                      color: '$i:' == '$_caretInfo'
                                          ? scheme.primary
                                          : scheme.outline,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
            // ── Code field ──
            Positioned.fill(
              left: _gutterWidth,
              child: Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Scrollbar(
                  controller: _scroll,
                  thumbVisibility: true,
                  child: TextField(
                    controller: _ctrl,
                    scrollController: _scroll,
                    onChanged: _onChanged,
                    keyboardType: TextInputType.multiline,
                    maxLines: null,
                    minLines: null,
                    expands: false,
                    autocorrect: false,
                    enableSuggestions: false,
                    style: TextStyle(
                      fontSize: _fontSize,
                      height: _lineHeight,
                      color: scheme.onSurface,
                      fontFamilyFallback: const [
                        'Consolas',
                        'DejaVu Sans Mono',
                        'monospace',
                      ],
                    ),
                    decoration: const InputDecoration(
                      isDense: true,
                      filled: false,
                      contentPadding: EdgeInsets.only(
                          top: 10, bottom: 40, right: 24),
                      border: InputBorder.none,
                      focusedBorder: InputBorder.none,
                    ),
                  ),
                ),
              ),
            ),
            // ── Ln:Col pill ──
            Positioned(
              right: 18,
              bottom: 10,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                      color: scheme.outlineVariant.withValues(alpha: 0.7)),
                ),
                child: Text(
                  '$_caretInfo  ·  $lineCount строк',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


