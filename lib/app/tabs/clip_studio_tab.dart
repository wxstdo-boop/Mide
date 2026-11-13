part of '../../main.dart';

// ---------------------------------------------------------------------------
// Clip Studio tab — a lightweight CapCut-style editor.
//
// Pick media → trim / speed / volume / colour-grade each clip → reorder on a
// horizontal timeline → export a single MP4 through FFmpeg. All edits are
// non-destructive: the project is a list of [ClipEdit]s and the export step
// renders normalised intermediates that are concatenated with `-c copy`.
// ---------------------------------------------------------------------------

class ClipStudioTab extends ConsumerStatefulWidget {
  const ClipStudioTab({super.key});

  @override
  ConsumerState<ClipStudioTab> createState() => _ClipStudioTabState();
}

class _ClipStudioTabState extends ConsumerState<ClipStudioTab> {
  int _selected = 0;
  bool _picking = false;

  Future<void> _addClips() async {
    if (_picking) return;
    setState(() => _picking = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.media,
      );
      if (result == null || result.files.isEmpty) return;
      final notifier = ref.read(clipProjectProvider.notifier);
      final picked = <ClipEdit>[];
      for (final f in result.files) {
        final path = f.path;
        if (path == null) continue; // Web without a path: not supported yet.
        final probe = await clipExporter.probe(path);
        final isImage = _looksLikeImage(f.extension);
        picked.add(ClipEdit(
          path: path,
          name: f.name,
          kind: isImage ? ClipKind.image : probe.kind,
          duration: isImage ? 3.0 : probe.duration,
        ));
      }
      if (picked.isEmpty) {
        _toast('Не удалось добавить файлы');
        return;
      }
      notifier.addClips(picked);
      setState(() => _selected =
          (ref.read(clipProjectProvider).clips.length - picked.length)
              .clamp(0, 1 << 30));
    } catch (e) {
      _toast('Ошибка выбора файлов: $e');
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  static bool _looksLikeImage(String? ext) {
    const images = {'png', 'jpg', 'jpeg', 'webp', 'gif', 'bmp', 'heic'};
    return ext != null && images.contains(ext.toLowerCase());
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  void _export() {
    final project = ref.read(clipProjectProvider);
    if (project.isEmpty) {
      _toast('Сначала добавь клипы');
      return;
    }
    ref.read(clipExportProvider.notifier).run(project);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final project = ref.watch(clipProjectProvider);
    final exporter = ref.watch(clipExportProvider);
    final notifier = ref.read(clipProjectProvider.notifier);
    final clips = project.clips;
    final selectedIndex =
        clips.isEmpty ? -1 : _selected.clamp(0, clips.length - 1);
    final selected = selectedIndex >= 0 ? clips[selectedIndex] : null;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: _AppHeader(
                image: 'assets/icon/mide.png',
                title: 'Clip Studio',
                version: '0.9b',
                actions: [
                  IconButton.filledTonal(
                    tooltip: 'Добавить медиа',
                    onPressed: _picking ? null : _addClips,
                    icon: const Icon(Icons.add_photo_alternate_rounded),
                  ),
                ],
              ),
            ),
            // Scrollable middle: preview → timeline → inspector. Scrolling
            // keeps the layout safe on short screens where a fixed Column
            // would overflow.
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
                children: [
                  SizedBox(
                    height: 260,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Center(child: ClipPreview(clip: selected)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _Timeline(
                    clips: clips,
                    selectedIndex: selectedIndex,
                    onSelect: (i) => setState(() => _selected = i),
                    onMove: notifier.moveTo,
                    onRemove: (i) {
                      notifier.removeAt(i);
                      setState(() => _selected = _selected.clamp(
                          0, math.max(0, clips.length - 2)));
                    },
                    onDuplicate: (i) {
                      notifier.duplicateAt(i);
                      setState(() => _selected = i + 1);
                    },
                    totalLabel: _fmtSeconds(project.totalDuration),
                  ),
                  if (selected == null)
                    SizedBox(
                      height: 200,
                      child: _EmptyHint(scheme: scheme, onAdd: _addClips),
                    )
                  else
                    _ClipInspector(
                      clip: selected,
                      onChanged: (c) => notifier.updateAt(selectedIndex, c),
                    ),
                ],
              ),
            ),
            _ExportBar(
              project: project,
              exporter: exporter,
              onCanvas: notifier.setCanvas,
              onFps: notifier.setFps,
              onExport: _export,
              onCancel: ref.read(clipExportProvider.notifier).cancel,
              onClear: () {
                notifier.clear();
                setState(() => _selected = 0);
              },
              onDoneToast: _toast,
            ),
          ],
        ),
      ),
    );
  }

  static String _fmtSeconds(double s) {
    final m = (s ~/ 60).toString().padLeft(2, '0');
    final sec = (s % 60).floor().toString().padLeft(2, '0');
    return '$m:$sec';
  }
}

// ── Timeline ───────────────────────────────────────────────────────────────

class _Timeline extends StatelessWidget {
  const _Timeline({
    required this.clips,
    required this.selectedIndex,
    required this.onSelect,
    required this.onMove,
    required this.onRemove,
    required this.onDuplicate,
    required this.totalLabel,
  });

  final List<ClipEdit> clips;
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final void Function(int oldIndex, int newIndex) onMove;
  final ValueChanged<int> onRemove;
  final ValueChanged<int> onDuplicate;
  final String totalLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (clips.isEmpty) {
      return SizedBox(
        height: 96,
        child: Center(
          child: Text(
            'Таймлайн пуст',
            style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
          ),
        ),
      );
    }
    return SizedBox(
      height: 108,
      child: ReorderableListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        buildDefaultDragHandles: false,
        itemCount: clips.length + 1,
        onReorderItem: onMove,
        footer: Padding(
          padding: const EdgeInsets.only(left: 8),
          child: Center(
            child: Text(
              totalLabel,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
        itemBuilder: (context, i) {
          if (i == clips.length) {
            return const SizedBox(width: 8);
          }
          final clip = clips[i];
          return ReorderableDelayedDragStartListener(
            key: ValueKey('${clip.path}_$i'),
            index: i,
            child: _ClipTile(
              clip: clip,
              selected: i == selectedIndex,
              onTap: () => onSelect(i),
              onRemove: () => onRemove(i),
              onDuplicate: () => onDuplicate(i),
            ),
          );
        },
      ),
    );
  }
}

class _ClipTile extends StatelessWidget {
  const _ClipTile({
    required this.clip,
    required this.selected,
    required this.onTap,
    required this.onRemove,
    required this.onDuplicate,
  });

  final ClipEdit clip;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onRemove;
  final VoidCallback onDuplicate;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final icon = switch (clip.kind) {
      ClipKind.image => Icons.image_rounded,
      ClipKind.audio => Icons.audiotrack_rounded,
      ClipKind.video => Icons.movie_rounded,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onDuplicate,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 108,
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? scheme.primary
                  : scheme.outlineVariant.withValues(alpha: 0.6),
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer.withValues(alpha: 0.5),
                    borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(13)),
                  ),
                  child: Icon(icon, color: scheme.primary),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 4, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        clip.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 10.5, color: scheme.onSurface),
                      ),
                    ),
                    InkWell(
                      onTap: onRemove,
                      child: Icon(Icons.close_rounded,
                          size: 15, color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Inspector ──────────────────────────────────────────────────────────────

class _ClipInspector extends StatelessWidget {
  const _ClipInspector({required this.clip, required this.onChanged});

  final ClipEdit clip;
  final ValueChanged<ClipEdit> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dur = clip.duration;
    final hasTrim = clip.kind != ClipKind.image && dur != null && dur > 0.2;
    final d = dur ?? 0.0;
    final end = (clip.trimEnd ?? d).clamp(clip.trimStart, d == 0 ? 1.0 : d);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      children: [
        if (hasTrim) ...[
          _LabelRow('Обрезка', '${end.toStringAsFixed(1)} с'),
          RangeSlider(
            values: RangeValues(
                clip.trimStart.clamp(0.0, d).toDouble(), end.toDouble()),
            max: d,
            onChanged: (r) => onChanged(clip.copyWith(
              trimStart: r.start,
              trimEnd: r.end,
            )),
          ),
        ],
        _LabelRow('Скорость', '${clip.speed.toStringAsFixed(2)}×'),
        Slider(
          value: clip.speed.clamp(0.25, 4.0),
          min: 0.25,
          max: 4.0,
          divisions: 15,
          onChanged: (v) => onChanged(clip.copyWith(speed: v)),
        ),
        if (clip.hasAudio) ...[
          _LabelRow('Громкость',
              clip.muted ? 'выкл' : '${(clip.volume * 100).round()}%'),
          Row(
            children: [
              Expanded(
                child: Slider(
                  value: clip.volume.clamp(0.0, 1.0),
                  onChanged: clip.muted
                      ? null
                      : (v) => onChanged(clip.copyWith(volume: v)),
                ),
              ),
              IconButton(
                tooltip: clip.muted ? 'Включить звук' : 'Выключить звук',
                onPressed: () => onChanged(clip.copyWith(muted: !clip.muted)),
                icon: Icon(clip.muted
                    ? Icons.volume_off_rounded
                    : Icons.volume_up_rounded),
              ),
            ],
          ),
        ],
        const SizedBox(height: 4),
        Text(
          'Фильтр',
          style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 36,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: ClipFilter.values.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final f = ClipFilter.values[i];
              final selected = f == clip.filter;
              return ChoiceChip(
                label: Text(f.label),
                selected: selected,
                onSelected: (_) => onChanged(clip.copyWith(filter: f)),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _LabelRow extends StatelessWidget {
  const _LabelRow(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurface)),
          Text(value,
              style:
                  TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.scheme, required this.onAdd});
  final ColorScheme scheme;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.video_settings_rounded,
              size: 44, color: scheme.onSurfaceVariant),
          const SizedBox(height: 10),
          Text(
            'Выбери видео, фото или музыку',
            style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            onPressed: onAdd,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Добавить медиа'),
          ),
        ],
      ),
    );
  }
}

// ── Export bar ─────────────────────────────────────────────────────────────

class _ExportBar extends StatelessWidget {
  const _ExportBar({
    required this.project,
    required this.exporter,
    required this.onCanvas,
    required this.onFps,
    required this.onExport,
    required this.onCancel,
    required this.onClear,
    required this.onDoneToast,
  });

  final ClipProject project;
  final ExportState exporter;
  final ValueChanged<CanvasPreset> onCanvas;
  final ValueChanged<int> onFps;
  final VoidCallback onExport;
  final VoidCallback onCancel;
  final VoidCallback onClear;
  final ValueChanged<String> onDoneToast;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (exporter.busy) ...[
            Row(
              children: [
                Expanded(
                  child: LinearProgressIndicator(
                    value: exporter.progress,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(width: 12),
                Text('${(exporter.progress * 100).round()}%',
                    style: TextStyle(
                        fontSize: 12, color: scheme.onSurfaceVariant)),
              ],
            ),
            const SizedBox(height: 10),
          ],
          if (exporter.phase == ExportPhase.failed &&
              exporter.message != null) ...[
            Text(exporter.message!,
                style: TextStyle(fontSize: 12, color: scheme.error)),
            const SizedBox(height: 8),
          ],
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<CanvasPreset>(
                  initialValue: project.canvas,
                  isDense: true,
                  decoration: const InputDecoration(
                    labelText: 'Кадр',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final c in CanvasPreset.values)
                      DropdownMenuItem(value: c, child: Text(c.label)),
                  ],
                  onChanged: exporter.busy
                      ? null
                      : (c) => c == null ? null : onCanvas(c),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 96,
                child: DropdownButtonFormField<int>(
                  initialValue: project.fps,
                  isDense: true,
                  decoration: const InputDecoration(
                    labelText: 'FPS',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 24, child: Text('24')),
                    DropdownMenuItem(value: 30, child: Text('30')),
                    DropdownMenuItem(value: 60, child: Text('60')),
                  ],
                  onChanged:
                      exporter.busy ? null : (v) => v == null ? null : onFps(v),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              IconButton(
                tooltip: 'Очистить проект',
                onPressed: exporter.busy ? null : onClear,
                icon: const Icon(Icons.delete_sweep_rounded),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: FilledButton.icon(
                  onPressed: exporter.busy
                      ? null
                      : (project.isEmpty ? null : onExport),
                  icon: Icon(exporter.busy
                      ? Icons.hourglass_top_rounded
                      : Icons.save_alt_rounded),
                  label: Text(exporter.busy ? 'Экспорт…' : 'Экспорт MP4'),
                ),
              ),
              if (exporter.busy) ...[
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Отменить',
                  onPressed: onCancel,
                  icon: const Icon(Icons.stop_circle_rounded),
                ),
              ],
            ],
          ),
          if (exporter.phase == ExportPhase.done &&
              exporter.outputPath != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: InkWell(
                onTap: () => onDoneToast('Файл: ${exporter.outputPath}'),
                child: Text(
                  'Сохранено: ${exporter.outputPath}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: scheme.primary),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
