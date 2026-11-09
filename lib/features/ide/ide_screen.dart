// PC-only IDE — main screen: toolbar, file tree, editor, console, AI panel.
// Only reachable from the AI section's IdeEntryPill on desktop builds.
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ide_ai.dart';
import 'ide_ai_panel.dart';
import 'ide_console.dart';
import 'ide_editor.dart';
import 'ide_providers.dart';
import 'ide_tree.dart';

/// Full IDE window for the PC build of Mide.
class IdeScreen extends ConsumerStatefulWidget {
  const IdeScreen({super.key});

  @override
  ConsumerState<IdeScreen> createState() => _IdeScreenState();
}

class _IdeScreenState extends ConsumerState<IdeScreen> {
  final _pathCtrl = TextEditingController();

  bool _treeVisible = true;
  bool _consoleVisible = true;
  bool _aiVisible = true;

  @override
  void dispose() {
    _pathCtrl.dispose();
    super.dispose();
  }

  // ── Actions ──────────────────────────────────────────────────────────────

  Future<void> _pickFolder() async {
    final dir = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Открыть папку проекта',
    );
    if (dir == null) return;
    _openPath(dir);
  }

  void _openPath(String raw) {
    final err = ref.read(ideWorkspaceProvider.notifier).openFolder(raw);
    if (err != null) {
      _snack(err);
    } else {
      _pathCtrl.clear();
    }
  }

  Future<void> _openFile(String path) async {
    final err = await ref.read(ideTabsProvider.notifier).openFile(path);
    if (err != null) _snack(err);
  }

  /// Small modal prompt for a file/folder name. Returns null on cancel.
  Future<String?> _promptName(String title, {String initial = ''}) {
    return showDialog<String>(
      context: context,
      builder: (ctx) {
        final ctrl = TextEditingController(text: initial);
        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            autocorrect: false,
            decoration: const InputDecoration(hintText: 'имя'),
            onSubmitted: (v) => Navigator.pop(ctx, v),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: const Text('Ок'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _createEntry({required bool asDir, required String parent}) async {
    final name = await _promptName(asDir ? 'Новая папка' : 'Новый файл');
    if (name == null || name.trim().isEmpty) return;
    final ws = ref.read(ideWorkspaceProvider.notifier);
    final err = ws.createEntry(
      parentPath: parent,
      asDir: asDir,
      name: name.trim(),
    );
    if (err != null) {
      _snack(err);
      return;
    }
    if (!asDir && ws.createdPath != null) {
      await _openFile(ws.createdPath!);
    }
  }

  Future<void> _renameNode(String path) async {
    final name = await _promptName('Переименовать', initial: ideBaseName(path));
    if (name == null || name.trim().isEmpty) return;
    final err = ref.read(ideWorkspaceProvider.notifier).rename(path, name);
    if (err != null) _snack(err);
  }

  Future<void> _deleteNode(IdeFsNode node) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Удалить «${node.name}»?'),
        content: Text(node.isDir
            ? 'Папка и всё её содержимое будут удалены с диска.'
            : 'Файл будет удалён с диска.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final err = ref.read(ideWorkspaceProvider.notifier).delete(node.path);
    ref.read(ideTabsProvider.notifier).closePath(node.path);
    if (err != null) _snack(err);
  }

  Future<void> _saveActive() async {
    final err = await ref.read(ideTabsProvider.notifier).save();
    _snack(err ?? 'Сохранено ✓');
  }

  Future<void> _runActive() async {
    final path = ref.read(ideTabsProvider).activeTab?.path;
    if (path == null) {
      _snack('Открой файл, чтобы запустить');
      return;
    }
    // Persist buffers first so the runner sees fresh code.
    await ref.read(ideTabsProvider.notifier).save(path: path);
    if (!_consoleVisible) setState(() => _consoleVisible = true);
    await ref.read(ideConsoleProvider.notifier).run(path);
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ws = ref.watch(ideWorkspaceProvider);
    final ts = ref.watch(ideTabsProvider);
    final dirty = ts.tabs.any((t) => t.dirty);

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f5): _runActive,
        const SingleActivator(LogicalKeyboardKey.keyS, control: true):
            _saveActive,
      },
      child: Scaffold(
        backgroundColor: scheme.surface,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Toolbar ──
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLow,
                  border: Border(
                    bottom: BorderSide(
                        color: scheme.outlineVariant.withValues(alpha: 0.5)),
                  ),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 28,
                      height: 28,
                      child: Image.asset('assets/icon/mide.png',
                          fit: BoxFit.cover),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Mide IDE',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: scheme.tertiaryContainer,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        'ХАЛЯВНЫЙ КОДИНГ',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                          color: scheme.onTertiaryContainer,
                        ),
                      ),
                    ),
                    const Spacer(),
                    _TopBtn(
                      icon: Icons.folder_open_rounded,
                      label: 'Открыть…',
                      onTap: _pickFolder,
                    ),
                    const SizedBox(width: 4),
                    _TopBtn(
                      icon: Icons.note_add_outlined,
                      tooltip: 'Новый файл',
                      onTap: ws.isOpen
                          ? () => _createEntry(asDir: false, parent: ws.root!)
                          : null,
                    ),
                    _TopBtn(
                      icon: Icons.create_new_folder_outlined,
                      tooltip: 'Новая папка',
                      onTap: ws.isOpen
                          ? () => _createEntry(asDir: true, parent: ws.root!)
                          : null,
                    ),
                    const SizedBox(width: 6),
                    _TopBtn(
                      icon: Icons.save_rounded,
                      label: 'Сохранить',
                      active: dirty,
                      onTap: ts.tabs.isEmpty ? null : _saveActive,
                    ),
                    const SizedBox(width: 4),
                    _TopBtn(
                      icon: Icons.play_arrow_rounded,
                      label: 'Запустить',
                      accent: true,
                      onTap: ts.tabs.isEmpty ? null : _runActive,
                    ),
                    const SizedBox(width: 10),
                    _TopBtn(
                      icon: Icons.menu_rounded,
                      tooltip: 'Файлы',
                      active: _treeVisible,
                      onTap: () =>
                          setState(() => _treeVisible = !_treeVisible),
                    ),
                    _TopBtn(
                      icon: Icons.terminal_rounded,
                      tooltip: 'Консоль',
                      active: _consoleVisible,
                      onTap: () =>
                          setState(() => _consoleVisible = !_consoleVisible),
                    ),
                    _TopBtn(
                      icon: Icons.auto_awesome_rounded,
                      tooltip: 'Кодинг-ИИ',
                      active: _aiVisible,
                      onTap: () => setState(() => _aiVisible = !_aiVisible),
                    ),
                    _TopBtn(
                      icon: Icons.settings_rounded,
                      tooltip: 'Инструменты (пути dart/python/node)',
                      onTap: _showToolsDialog,
                    ),
                  ],
                ),
              ),
              // ── Workspace ──
              Expanded(
                child: ws.isOpen
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_treeVisible)
                            SizedBox(
                              width: 252,
                              child: IdeFileTree(
                                onOpenFile: _openFile,
                                onCreateFile: (p) =>
                                    _createEntry(asDir: false, parent: p),
                                onCreateFolder: (p) =>
                                    _createEntry(asDir: true, parent: p),
                                onRename: _renameNode,
                                onDelete: _deleteNode,
                              ),
                            ),
                          if (_treeVisible)
                            const SizedBox(
                              width: 1,
                              child: ColoredBox(color: Color(0x33888888)),
                            ),
                          Expanded(
                            child: Column(
                              children: [
                                const IdeTabStrip(),
                                Expanded(
                                  child: IdeEditorPane(
                                    emptyHint: _emptyEditor(context),
                                  ),
                                ),
                                if (_consoleVisible)
                                  const SizedBox(
                                    height: 218,
                                    child: IdeConsolePanel(),
                                  ),
                              ],
                            ),
                          ),
                          if (_aiVisible)
                            const SizedBox(
                              width: 344,
                              child: IdeAiPanel(),
                            ),
                        ],
                      )
                    : _emptyWorkspace(context),
              ),
              // ── Status bar ──
              _buildStatusBar(context),

            ],
          ),
        ),
      ),
    );
  }

  /// ⚙ interpreter paths dialog trigger.
  void _showToolsDialog() {
    showDialog<void>(
      context: context,
      builder: (_) => const _ToolsDialog(),
    );
  }

  /// Welcome state: open a folder (picker or typed path) + feature chips.
  Widget _emptyWorkspace(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 92,
                height: 92,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [
                    scheme.primary.withValues(alpha: 0.22),
                    scheme.primary.withValues(alpha: 0.03),
                  ]),
                  border:
                      Border.all(color: scheme.primary.withValues(alpha: 0.4)),
                ),
                child:
                    Icon(Icons.folder_open_rounded, size: 42, color: scheme.primary),
              ),
              const SizedBox(height: 20),
              Text(
                'Открой папку проекта',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                  color: scheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Дерево файлов, редактор с нумерацией строк, консоль\n'
                'и бесплатный кодинг-ИИ — только на ПК.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 13.5,
                    height: 1.55,
                    color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _pickFolder,
                icon: const Icon(Icons.folder_open_rounded, size: 18),
                label: const Text('Открыть папку…'),
                style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 26, vertical: 16)),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _pathCtrl,
                      onSubmitted: _openPath,
                      decoration: const InputDecoration(
                        hintText: 'или вставь путь: D:\\project',
                        isDense: true,
                        prefixIcon: Icon(Icons.alt_route_rounded, size: 18),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Перейти',
                    onPressed: () => _openPath(_pathCtrl.text),
                    icon: const Icon(Icons.arrow_forward_rounded),
                    style: IconButton.styleFrom(
                      backgroundColor: scheme.primaryContainer,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              const Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  _FeatureChip(label: 'Файловое дерево'),
                  _FeatureChip(label: 'Ctrl+S · Tab · F5'),
                  _FeatureChip(label: 'Запуск dart/py/js'),
                  _FeatureChip(label: 'Kilo · OVHcloud · LLM7'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Placeholder shown in the editor pane when no file is open.
  Widget _emptyEditor(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.data_object_rounded, size: 40, color: scheme.outline),
          const SizedBox(height: 12),
          Text(
            'Выбери файл слева',
            style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.w600, color: scheme.outline),
          ),
          const SizedBox(height: 6),
          Text(
            'Ctrl+S — сохранить · Tab — отступ · F5 — запустить',
            style: TextStyle(fontSize: 12, color: scheme.outline),
          ),
        ],
      ),
    );
  }

  /// Thin data strip along the bottom: project, file, dirty state, hints.
  Widget _buildStatusBar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ws = ref.watch(ideWorkspaceProvider);
    final ts = ref.watch(ideTabsProvider);
    final ai = ref.watch(ideAiProvider);
    final tab = ts.activeTab;
    final dirty = tab?.dirty ?? false;

    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border(
          top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.folder_rounded, size: 12, color: scheme.primary),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              ws.root ?? 'проект не открыт',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
            ),
          ),
          if (tab != null) ...[
            const SizedBox(width: 10),
            Icon(Icons.insert_drive_file_outlined,
                size: 12, color: scheme.onSurfaceVariant),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                tab.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, color: scheme.onSurface),
              ),
            ),
            if (dirty) ...[
              const SizedBox(width: 6),
              Icon(Icons.circle, size: 7, color: scheme.tertiary),
              const SizedBox(width: 3),
              Text('не сохранено',
                  style: TextStyle(fontSize: 11, color: scheme.tertiary)),
            ],
          ],
          const Spacer(),
          Text(
            'Kilo · OVH · LLM7',
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: scheme.primary),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: scheme.secondaryContainer,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              ai.providerLabel,
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: scheme.onSecondaryContainer),
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact toolbar button: icon + optional label, with accent/active states.
class _TopBtn extends StatelessWidget {
  const _TopBtn({
    required this.icon,
    required this.onTap,
    this.label,
    this.tooltip,
    this.active = false,
    this.accent = false,
  });

  final IconData icon;
  final String? label;
  final String? tooltip;
  final VoidCallback? onTap;
  final bool active;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = onTap != null;
    final bg = accent
        ? scheme.primary
        : active
            ? scheme.primaryContainer
            : Colors.transparent;
    final fg = accent
        ? scheme.onPrimary
        : active
            ? scheme.primary
            : scheme.onSurfaceVariant;

    final child = Material(
      color: bg,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: label == null
              ? const EdgeInsets.all(8)
              : const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 17, color: enabled ? fg : scheme.outline),
              if (label != null) ...[
                const SizedBox(width: 7),
                Text(
                  label!,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: enabled ? fg : scheme.outline,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );

    final tip = tooltip ?? label;
    return tip == null ? child : Tooltip(message: tip, child: child);
  }
}

/// Small outlined feature chip for the welcome screen.
class _FeatureChip extends StatelessWidget {
  const _FeatureChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(999),
        border:
            Border.all(color: scheme.primary.withValues(alpha: 0.30)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Modal with interpreter paths (dart/python/node/pwsh). Empty = look up
/// in PATH; values persist in secure storage.
class _ToolsDialog extends ConsumerStatefulWidget {
  const _ToolsDialog();

  @override
  ConsumerState<_ToolsDialog> createState() => _ToolsDialogState();
}

class _ToolsDialogState extends ConsumerState<_ToolsDialog> {
  late final TextEditingController _dart;
  late final TextEditingController _python;
  late final TextEditingController _node;
  late final TextEditingController _pwsh;

  static const _fields = <(String, String, String)>[
    ('dart', 'Dart / Flutter', 'например C:\\Flutter\\flutter\\bin\\dart.exe'),
    ('python', 'Python', 'python.exe или пусто = PATH'),
    ('node', 'Node.js', 'node.exe или пусто = PATH'),
    ('pwsh', 'PowerShell', 'pwsh.exe / powershell.exe'),
  ];

  @override
  void initState() {
    super.initState();
    final tools = ref.read(ideToolsProvider);
    _dart = TextEditingController(text: tools.of('dart') ?? '');
    _python = TextEditingController(text: tools.of('python') ?? '');
    _node = TextEditingController(text: tools.of('node') ?? '');
    _pwsh = TextEditingController(text: tools.of('pwsh') ?? '');
  }

  @override
  void dispose() {
    _dart.dispose();
    _python.dispose();
    _node.dispose();
    _pwsh.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final controllers = [_dart, _python, _node, _pwsh];

    return AlertDialog(
      title: const Text('Инструменты запуска'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Пустое поле = искать в PATH. Значения сохраняются локально.',
              style: TextStyle(
                  fontSize: 12.5, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 14),
            for (var i = 0; i < _fields.length; i++) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    SizedBox(
                      width: 110,
                      child: Text(
                        _fields[i].$2,
                        style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: scheme.onSurface),
                      ),
                    ),
                    Expanded(
                      child: TextField(
                        controller: controllers[i],
                        autocorrect: false,
                        decoration: InputDecoration(
                          hintText: _fields[i].$3,
                          isDense: true,
                          prefixIcon: const Icon(Icons.terminal_rounded,
                              size: 16),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            Text(
              'Поддерживаются: .dart .py .js .ps1 .bat .sh — кнопка ▶ или F5.',
              style: TextStyle(fontSize: 11.5, color: scheme.outline),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () async {
            final notifier = ref.read(ideToolsProvider.notifier);
            for (var i = 0; i < _fields.length; i++) {
              await notifier.set(_fields[i].$1, controllers[i].text);
            }
            if (context.mounted) Navigator.pop(context);
          },
          child: const Text('Сохранить'),
        ),
      ],
    );
  }
}





