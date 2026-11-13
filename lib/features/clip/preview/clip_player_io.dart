// Video preview player for Clip Studio.
//
// video_player has no Windows/Linux implementation, so on those platforms we
// fall back to a lightweight placeholder that still shows the current frame's
// metadata and the transport controls. Android/iOS/macOS/Web get the real
// player via clip_player_io.dart.
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:video_player/video_player.dart';

import '../clip_models.dart';

class ClipPreview extends StatefulWidget {
  const ClipPreview({super.key, required this.clip});

  final ClipEdit? clip;

  @override
  State<ClipPreview> createState() => _ClipPreviewState();
}

class _ClipPreviewState extends State<ClipPreview> {
  VideoPlayerController? _controller;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _open();
  }

  @override
  void didUpdateWidget(covariant ClipPreview old) {
    super.didUpdateWidget(old);
    if (old.clip?.path != widget.clip?.path) _open();
  }

  Future<void> _open() async {
    final c = _controller;
    _controller = null;
    await c?.dispose();
    _failed = false;
    final clip = widget.clip;
    if (clip == null || clip.kind == ClipKind.audio) {
      if (mounted) setState(() {});
      return;
    }
    final controller = VideoPlayerController.file(File(clip.path));
    try {
      await controller.initialize();
      await controller.seekTo(Duration(milliseconds: (clip.trimStart * 1000).round()));
      await controller.setVolume(clip.muted ? 0 : clip.volume);
      await controller.setPlaybackSpeed(clip.speed.clamp(0.25, 4.0));
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
    } catch (_) {
      await controller.dispose();
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final clip = widget.clip;
    if (clip == null) {
      return _placeholder(scheme, Icons.movie_filter_rounded, 'Добавь клип');
    }
    final controller = _controller;
    if (controller != null && controller.value.isInitialized) {
      return AspectRatio(
        aspectRatio: controller.value.aspectRatio,
        child: Stack(
          alignment: Alignment.bottomCenter,
          children: [
            VideoPlayer(controller),
            _transport(scheme, controller),
          ],
        ),
      );
    }
    return _placeholder(
      scheme,
      clip.kind == ClipKind.audio
          ? Icons.audiotrack_rounded
          : Icons.videocam_rounded,
      _failed ? 'Нет превью для этого файла' : clip.name,
    );
  }

  Widget _transport(ColorScheme scheme, VideoPlayerController c) {
    return AnimatedBuilder(
      animation: c,
      builder: (context, _) {
        final playing = c.value.isPlaying;
        return Container(
          margin: const EdgeInsets.all(8),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                iconSize: 22,
                color: Colors.white,
                onPressed: () => playing ? c.pause() : c.play(),
                icon: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
              ),
              Text(
                '${_fmt(c.value.position)} / ${_fmt(c.value.duration)}',
                style: const TextStyle(color: Colors.white, fontSize: 11.5),
              ),
              const SizedBox(width: 6),
            ],
          ),
        );
      },
    );
  }

  Widget _placeholder(ColorScheme scheme, IconData icon, String label) {
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 34, color: scheme.onSurfaceVariant),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }

  static String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}
