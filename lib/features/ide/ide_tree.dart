// PC-only IDE — left file tree panel.
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ide_providers.dart';

/// Left sidebar: workspace tree with expand/collapse, selection and a
/// compact toolbar (new file / new folder / refresh / close).
class IdeFileTree extends ConsumerWidget {
  const IdeFileTree({
    super.key,
    required this.onOpenFile,
    required this.onCreateFile,
    required this.onCreateFolder,
    required this.onRename,
    required this.onDelete,
  });

  final ValueChanged<String> onOpenFile;
  final void Function(String parentPath) onCreateFile;
  final void Function(String parentPath) onCreateFolder;
  final void Function(String path) onRename;
  final void Function(IdeFsNode node) onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final ws = ref.watch(ideWorkspaceProvider);
    final root = ws.root;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border(
          right: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Sidebar toolbar ──
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 6),
            child: Row(
              children: [
                Icon(
                  Icons.folder_open_rounded,
                  size: 16,
                  color: scheme.primary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    root == null ? 'Проект' : ideBaseName(root),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: scheme.onSurface,
                    ),
                  ),
                ),
                _TreeIconBtn(
                  tooltip: 'Новый файл',
                  icon: Icons.note_add_outlined,
                  onTap: root == null ? null : () => onCreateFile(root),
                ),
                _TreeIconBtn(
                  tooltip: 'Новая папка',
                  icon: Icons.create_new_folder_outlined,
                  onTap: root == null ? null : () => onCreateFolder(root),
                ),
                _TreeIconBtn(
                  tooltip: 'Обновить',
                  icon: Icons.refresh_rounded,
                  onTap: root == null
                      ? null
                      : ref.read(ideWorkspaceProvider.notifier).refresh,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // ── Tree ──
          Expanded(
            child: root == null
                ? Center(
                    child: Text(
                      'Открой папку проекта',
                      style: TextStyle(fontSize: 12, color: scheme.outline),
                    ),
                  )
                : Scrollbar(
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: _buildLevel(context, ref, root, 0),
                    ),
                  ),
          ),
          if (ws.error != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              color: scheme.errorContainer,
              child: Text(
                ws.error!,
                style: TextStyle(
                  fontSize: 11.5,
                  color: scheme.onErrorContainer,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Renders one directory level; folders recurse into themselves.
  Widget _buildLevel(
    BuildContext context,
    WidgetRef ref,
    String dirPath,
    int depth,
  ) {
    final ws = ref.watch(ideWorkspaceProvider);
    final nodes = ws.children[dirPath] ?? const <IdeFsNode>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final node in nodes) ...[
          _TreeTile(
            node: node,
            depth: depth,
            selected: ws.selected == node.path,
            expanded: ws.expanded.contains(node.path),
            onTap: () {
              ref.read(ideWorkspaceProvider.notifier).select(node.path);
              if (node.isDir) {
                ref.read(ideWorkspaceProvider.notifier).toggle(node.path);
              } else {
                onOpenFile(node.path);
              }
            },
            onRename: () => onRename(node.path),
            onDelete: () => onDelete(node),
          ),
          if (node.isDir && ws.expanded.contains(node.path))
            _buildLevel(context, ref, node.path, depth + 1),
        ],
      ],
    );
  }
}

// ── Row pieces ─────────────────────────────────────────────────────────────

/// One tree row: disclosure caret + type icon + name + menu button.
class _TreeTile extends StatelessWidget {
  const _TreeTile({
    required this.node,
    required this.depth,
    required this.selected,
    required this.expanded,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
  });

  final IdeFsNode node;
  final int depth;
  final bool selected;
  final bool expanded;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Tooltip(
        message: node.path,
        waitDuration: const Duration(milliseconds: 700),
        child: Container(
          height: 30,
          margin: EdgeInsets.fromLTRB(6 + depth * 14.0, 1, 6, 1),
          padding: const EdgeInsets.only(right: 2),
          decoration: BoxDecoration(
            color: selected ? scheme.primaryContainer : null,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 22,
                height: 30,
                child: node.isDir
                    ? Icon(
                        expanded
                            ? Icons.expand_more_rounded
                            : Icons.chevron_right_rounded,
                        size: 17,
                        color: scheme.onSurfaceVariant,
                      )
                    : const SizedBox.shrink(),
              ),
              Icon(
                node.isDir
                    ? (expanded
                          ? Icons.folder_open_rounded
                          : Icons.folder_rounded)
                    : _fileIcon(node.name),
                size: 16,
                color: node.isDir
                    ? scheme.primary
                    : _fileColor(scheme, node.name),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  node.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: scheme.onSurface,
                  ),
                ),
              ),
              PopupMenuButton<String>(
                padding: EdgeInsets.zero,
                icon: Icon(
                  Icons.more_horiz_rounded,
                  size: 16,
                  color: scheme.outline,
                ),
                iconSize: 16,
                onSelected: (v) {
                  if (v == 'rename') onRename();
                  if (v == 'delete') onDelete();
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'rename',
                    child: Row(
                      children: [
                        Icon(
                          Icons.edit_rounded,
                          size: 16,
                          color: scheme.onSurface,
                        ),
                        const SizedBox(width: 8),
                        const Text('Переименовать'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(
                          Icons.delete_rounded,
                          size: 16,
                          color: scheme.error,
                        ),
                        const SizedBox(width: 8),
                        Text('Удалить', style: TextStyle(color: scheme.error)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static IconData _fileIcon(String name) {
    final dot = name.lastIndexOf('.');
    switch (dot < 0 ? '' : name.substring(dot + 1).toLowerCase()) {
      case 'dart':
        return Icons.terminal_rounded;
      case 'json':
        return Icons.data_object_rounded;
      case 'md':
        return Icons.article_outlined;
      case 'png':
      case 'jpg':
      case 'jpeg':
      case 'gif':
      case 'webp':
        return Icons.image_outlined;
      case 'html':
        return Icons.language_rounded;
      case 'css':
        return Icons.palette_outlined;
      case 'yaml':
      case 'yml':
        return Icons.settings_outlined;
      default:
        return Icons.insert_drive_file_outlined;
    }
  }

  static Color _fileColor(ColorScheme scheme, String name) {
    final dot = name.lastIndexOf('.');
    switch (dot < 0 ? '' : name.substring(dot + 1).toLowerCase()) {
      case 'dart':
        return scheme.tertiary;
      case 'json':
        return scheme.secondary;
      case 'md':
        return scheme.primary;
      default:
        return scheme.onSurfaceVariant;
    }
  }
}

/// Small ghost icon button used by the tree toolbar.
class _TreeIconBtn extends StatelessWidget {
  const _TreeIconBtn({
    required this.tooltip,
    required this.icon,
    required this.onTap,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IconButton(
      tooltip: tooltip,
      onPressed: onTap,
      icon: Icon(icon, size: 17),
      color: scheme.onSurfaceVariant,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
    );
  }
}
