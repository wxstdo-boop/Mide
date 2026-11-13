// Clip Studio export engine — Web stub.
//
// The FFmpeg plugin is native-only, so on Web the editor still builds and
// previews (local playback via video_player) but exporting is disabled with a
// clear message instead of a crash.
import 'clip_models.dart';

class ProbeResult {
  const ProbeResult({this.duration, this.kind = ClipKind.video});
  final double? duration;
  final ClipKind kind;
}

class ClipExporter {
  const ClipExporter();

  Future<ProbeResult> probe(String path) async => const ProbeResult();

  Future<String> export(
    ClipProject project, {
    void Function(double progress, String message)? onProgress,
  }) async {
    throw UnsupportedError('Экспорт видео недоступен в веб-версии');
  }

  void cancel() {}
}
