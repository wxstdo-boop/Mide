// Riverpod state for Clip Studio: the edit project and the export run.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'clip_export.dart';
import 'clip_models.dart';

/// The current edit project. Immutable value; every mutation swaps a new one.
class ClipProjectNotifier extends Notifier<ClipProject> {
  @override
  ClipProject build() => const ClipProject();

  void addClips(Iterable<ClipEdit> clips) {
    state = state.copyWith(clips: [...state.clips, ...clips]);
  }

  void removeAt(int index) {
    if (index < 0 || index >= state.clips.length) return;
    final next = [...state.clips]..removeAt(index);
    state = state.copyWith(clips: next);
  }

  void duplicateAt(int index) {
    if (index < 0 || index >= state.clips.length) return;
    final next = [...state.clips]..insert(index + 1, state.clips[index]);
    state = state.copyWith(clips: next);
  }

  void updateAt(int index, ClipEdit clip) {
    if (index < 0 || index >= state.clips.length) return;
    final next = [...state.clips]..[index] = clip;
    state = state.copyWith(clips: next);
  }

  /// Moves the clip at [oldIndex] to [newIndex] (ReorderableListView order).
  void reorder(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= state.clips.length) return;
    final next = [...state.clips];
    if (newIndex > oldIndex) newIndex -= 1;
    final item = next.removeAt(oldIndex);
    next.insert(newIndex.clamp(0, next.length), item);
    state = state.copyWith(clips: next);
  }

  /// Moves a clip to an already-adjusted target index (ReorderableListView's
  /// `onReorderItem`, which does not need the `newIndex - 1` correction).
  void moveTo(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= state.clips.length) return;
    final next = [...state.clips];
    final item = next.removeAt(oldIndex);
    next.insert(newIndex.clamp(0, next.length), item);
    state = state.copyWith(clips: next);
  }

  void setCanvas(CanvasPreset canvas) => state = state.copyWith(canvas: canvas);

  void setFps(int fps) => state = state.copyWith(fps: fps);

  void clear() => state = const ClipProject();
}

final clipProjectProvider = NotifierProvider<ClipProjectNotifier, ClipProject>(
  ClipProjectNotifier.new,
);

/// Runs and tracks a single export job.
class ClipExportNotifier extends Notifier<ExportState> {
  @override
  ExportState build() => const ExportState();

  Future<void> run(ClipProject project) async {
    if (state.busy) return;
    state = const ExportState(
      phase: ExportPhase.rendering,
      progress: 0,
      message: 'Подготовка…',
    );
    try {
      final path = await clipExporter.export(
        project,
        onProgress: (progress, message) {
          state = state.copyWith(
            phase: progress >= 1.0
                ? ExportPhase.done
                : (progress >= 0.97
                      ? ExportPhase.concat
                      : ExportPhase.rendering),
            progress: progress,
            message: message,
          );
        },
      );
      state = state.copyWith(
        phase: ExportPhase.done,
        progress: 1,
        message: 'Готово',
        outputPath: path,
      );
    } on ExportCancelled {
      state = const ExportState(phase: ExportPhase.idle);
    } on UnsupportedError catch (e) {
      state = ExportState(
        phase: ExportPhase.failed,
        message: e.message?.toString() ?? 'Экспорт недоступен',
      );
    } catch (e) {
      state = ExportState(
        phase: ExportPhase.failed,
        message: 'Ошибка экспорта: $e',
      );
    }
  }

  void cancel() {
    clipExporter.cancel();
    state = const ExportState(phase: ExportPhase.idle);
  }

  void reset() => state = const ExportState();
}

final clipExportProvider = NotifierProvider<ClipExportNotifier, ExportState>(
  ClipExportNotifier.new,
);
