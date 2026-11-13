// Clip Studio data model: clips, edits and export settings.
//
// Kept free of Flutter/plugin imports so the ffmpeg command builders and the
// project notifier stay unit-testable without a device.
import 'dart:math' as math;

/// Colour/grade presets applied per clip via ffmpeg filters.
enum ClipFilter {
  none('Оригинал'),
  mono('Ч/Б'),
  sepia('Сепия'),
  warm('Тепло'),
  cool('Холод'),
  vivid('Сочность'),
  vignette('Виньетка');

  const ClipFilter(this.label);
  final String label;
}

/// Where a media item came from — drives the render path.
enum ClipKind { video, image, audio }

/// A single item on the timeline, with all of its non-destructive edits.
class ClipEdit {
  const ClipEdit({
    required this.path,
    required this.name,
    required this.kind,
    this.duration,
    this.trimStart = 0,
    this.trimEnd,
    this.speed = 1.0,
    this.volume = 1.0,
    this.muted = false,
    this.filter = ClipFilter.none,
  });

  final String path;
  final String name;
  final ClipKind kind;

  /// Full source length in seconds, once probed. Null until known.
  final double? duration;

  /// Trim window in seconds, relative to the source.
  final double trimStart;
  final double? trimEnd;

  /// Playback rate multiplier, clamped to [0.25, 4].
  final double speed;
  final double volume;
  final bool muted;
  final ClipFilter filter;

  bool get hasAudio => kind != ClipKind.image;

  /// Source seconds actually used after trimming.
  double sourceWindow(double fallback) {
    final end = trimEnd ?? duration ?? fallback;
    return math.max(0, end - trimStart);
  }

  /// Output length in seconds after trim + speed.
  double outputDuration(double fallback) {
    final w = sourceWindow(fallback);
    if (kind == ClipKind.image || speed <= 0) return w;
    return w / speed;
  }

  ClipEdit copyWith({
    String? path,
    String? name,
    ClipKind? kind,
    double? duration,
    double? trimStart,
    double? trimEnd,
    bool clearTrimEnd = false,
    double? speed,
    double? volume,
    bool? muted,
    ClipFilter? filter,
  }) {
    return ClipEdit(
      path: path ?? this.path,
      name: name ?? this.name,
      kind: kind ?? this.kind,
      duration: duration ?? this.duration,
      trimStart: trimStart ?? this.trimStart,
      trimEnd: clearTrimEnd ? null : (trimEnd ?? this.trimEnd),
      speed: speed ?? this.speed,
      volume: volume ?? this.volume,
      muted: muted ?? this.muted,
      filter: filter ?? this.filter,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ClipEdit &&
      other.path == path &&
      other.name == name &&
      other.kind == kind &&
      other.duration == duration &&
      other.trimStart == trimStart &&
      other.trimEnd == trimEnd &&
      other.speed == speed &&
      other.volume == volume &&
      other.muted == muted &&
      other.filter == filter;

  @override
  int get hashCode => Object.hash(path, name, kind, duration, trimStart,
      trimEnd, speed, volume, muted, filter);
}

/// Output canvas presets.
enum CanvasPreset {
  vertical9x16('9:16', 1080, 1920),
  horizontal16x9('16:9', 1920, 1080),
  square1x1('1:1', 1080, 1080),
  hd720('720p', 1280, 720);

  const CanvasPreset(this.label, this.width, this.height);
  final String label;
  final int width;
  final int height;
}

/// Immutable project: ordered clips + export canvas.
class ClipProject {
  const ClipProject({
    this.clips = const <ClipEdit>[],
    this.canvas = CanvasPreset.vertical9x16,
    this.fps = 30,
  });

  final List<ClipEdit> clips;
  final CanvasPreset canvas;
  final int fps;

  bool get isEmpty => clips.isEmpty;

  /// Sum of every clip's trimmed, speed-adjusted length.
  double get totalDuration =>
      clips.fold(0, (sum, c) => sum + c.outputDuration(3.0));

  ClipProject copyWith({
    List<ClipEdit>? clips,
    CanvasPreset? canvas,
    int? fps,
  }) {
    return ClipProject(
      clips: clips ?? this.clips,
      canvas: canvas ?? this.canvas,
      fps: fps ?? this.fps,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ClipProject &&
      _listEq(other.clips, clips) &&
      other.canvas == canvas &&
      other.fps == fps;

  @override
  int get hashCode => Object.hash(Object.hashAll(clips), canvas, fps);

  static bool _listEq(List<ClipEdit> a, List<ClipEdit> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Progress/status of an export run.
enum ExportPhase { idle, rendering, concat, done, failed }

/// Thrown when the user cancels an in-flight export. The UI treats this as a
/// return to idle rather than a failure.
class ExportCancelled implements Exception {
  const ExportCancelled();
  @override
  String toString() => 'Экспорт отменён';
}

class ExportState {
  const ExportState({
    this.phase = ExportPhase.idle,
    this.progress = 0,
    this.message,
    this.outputPath,
  });

  final ExportPhase phase;
  final double progress; // 0..1
  final String? message;
  final String? outputPath;

  bool get busy =>
      phase == ExportPhase.rendering || phase == ExportPhase.concat;

  ExportState copyWith({
    ExportPhase? phase,
    double? progress,
    String? message,
    String? outputPath,
  }) {
    return ExportState(
      phase: phase ?? this.phase,
      progress: progress ?? this.progress,
      message: message ?? this.message,
      outputPath: outputPath ?? this.outputPath,
    );
  }
}
