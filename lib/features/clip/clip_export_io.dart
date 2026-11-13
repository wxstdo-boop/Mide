// Clip Studio export engine — the only place that touches the FFmpeg plugin
// and the filesystem. Desktop/mobile only; the Web build never imports this
// file (see clip_export.dart for the conditional facade).
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:path_provider/path_provider.dart';

import 'clip_ffmpeg.dart';
import 'clip_models.dart';

/// Result of probing a media file: length in seconds and its kind.
class ProbeResult {
  const ProbeResult({this.duration, this.kind = ClipKind.video});
  final double? duration;
  final ClipKind kind;
}

class ClipExporter {
  ClipExporter();

  bool _cancelled = false;

  /// Reads duration + media kind via ffprobe. Never throws: on failure it
  /// returns a video kind with an unknown duration so the UI can still add
  /// the clip and let the user set the length manually.
  Future<ProbeResult> probe(String path) async {
    try {
      final session = await FFprobeKit.getMediaInformation(path);
      final info = session.getMediaInformation();
      if (info == null) return const ProbeResult();
      final duration = parseDuration(info.getDuration());
      var hasVideo = false;
      var hasAudio = false;
      for (final s in info.getStreams()) {
        final t = s.getType();
        if (t == 'video') hasVideo = true;
        if (t == 'audio') hasAudio = true;
      }
      final kind = hasVideo
          ? ClipKind.video
          : (hasAudio ? ClipKind.audio : ClipKind.video);
      return ProbeResult(duration: duration, kind: kind);
    } catch (_) {
      return const ProbeResult();
    }
  }

  /// Renders the whole project to a single MP4 and returns its path.
  ///
  /// Two stages: each clip is normalised into an intermediate file (identical
  /// codec/canvas/fps/audio layout), then the parts are concatenated with
  /// `-c copy` so the final join needs no second encode.
  ///
  /// [onProgress] receives a 0..1 value and a short human-readable phase.
  Future<String> export(
    ClipProject project, {
    void Function(double progress, String message)? onProgress,
  }) async {
    if (project.clips.isEmpty) {
      throw StateError('Нет клипов для экспорта');
    }
    _cancelled = false;
    final report = onProgress ?? (double _, String __) {};

    final tmpRoot = await getTemporaryDirectory();
    final work = Directory(
      '${tmpRoot.path}${Platform.pathSeparator}'
      'mide_clip_${DateTime.now().millisecondsSinceEpoch}',
    );
    await work.create(recursive: true);

    final outDir = await getApplicationDocumentsDirectory();
    final outDirClip = Directory(
      '${outDir.path}${Platform.pathSeparator}Mide',
    );
    if (!outDirClip.existsSync()) {
      await outDirClip.create(recursive: true);
    }
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final outputPath =
        '${outDirClip.path}${Platform.pathSeparator}clip_$stamp.mp4';

    final total = project.totalDuration;
    var rendered = 0.0;
    final parts = <String>[];

    try {
      for (var i = 0; i < project.clips.length; i++) {
        if (_cancelled) throw const ExportCancelled();
        final clip = project.clips[i];
        final clipOut =
            '${work.path}${Platform.pathSeparator}part_$i.mp4';
        final clipDur = clip.outputDuration(3.0);
        final clipIndex = i + 1;

        report(
          total <= 0 ? 0 : (rendered / total).clamp(0, 1),
          'Рендер $clipIndex/${project.clips.length}',
        );

        final args =
            buildClipArgs(clip, project.canvas, project.fps, clipOut);
        final code = await _run(args, (ms) {
          if (total <= 0) return;
          final within = clipDur <= 0
              ? 0.0
              : (ms / 1000.0 / clipDur).clamp(0.0, 1.0);
          final p = ((rendered + within * clipDur) / total).clamp(0.0, 1.0);
          report(p, 'Рендер $clipIndex/${project.clips.length}');
        });
        if (code != null) {
          throw StateError('FFmpeg вернул ошибку на клипе $clipIndex');
        }
        parts.add(clipOut);
        rendered += clipDur;
      }

      if (_cancelled) throw const ExportCancelled();

      report(0.97, 'Склейка');
      final listFile =
          File('${work.path}${Platform.pathSeparator}list.txt');
      await listFile.writeAsString(buildConcatList(parts));
      final code =
          await _run(buildConcatArgs(listFile.path, outputPath), null);
      if (code != null) {
        throw StateError('FFmpeg вернул ошибку на склейке');
      }

      report(1.0, 'Готово');
      return outputPath;
    } finally {
      try {
        await work.delete(recursive: true);
      } catch (_) {
        // Best-effort cleanup; the OS reaps the temp dir anyway.
      }
    }
  }

  /// Runs one ffmpeg invocation. Returns null on success, else the return
  /// code value. [onTime] gets the elapsed output time in milliseconds.
  Future<int?> _run(
    List<String> args,
    void Function(int millis)? onTime,
  ) async {
    final session = await FFmpegKit.executeWithArgumentsAsync(
      args,
      null,
      null,
      onTime == null ? null : (stats) => onTime(stats.getTime()),
    );
    if (_cancelled) {
      await FFmpegKit.cancel(session.getSessionId());
      throw const ExportCancelled();
    }
    final rc = await session.getReturnCode();
    return ReturnCode.isSuccess(rc) ? null : (rc?.getValue() ?? -1);
  }

  /// Requests cancellation of the in-flight export.
  void cancel() {
    _cancelled = true;
    FFmpegKit.cancel();
  }
}
