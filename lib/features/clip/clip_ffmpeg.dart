// FFmpeg command builders for Clip Studio.
//
// Pure functions: given a clip (or a list of rendered parts) they return the
// full ffmpeg argument vector. Nothing here touches Flutter or the plugin, so
// every branch is unit-testable with a plain `expect`.
import 'clip_models.dart';

/// Seconds → ffmpeg-friendly literal (3 decimals, trailing zeros trimmed).
String ffSeconds(double s) {
  var v = s.toStringAsFixed(3);
  if (v.contains('.')) {
    v = v.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
  }
  return v.isEmpty ? '0' : v;
}

/// `atempo` only accepts 0.5–2.0, so extreme rates are chained.
String atempoChain(double speed) {
  final parts = <String>[];
  var s = speed;
  while (s > 2.0 + 1e-9) {
    parts.add('atempo=2.0');
    s /= 2.0;
  }
  while (s < 0.5 - 1e-9) {
    parts.add('atempo=0.5');
    s /= 0.5;
  }
  parts.add('atempo=${s.toStringAsFixed(4)}');
  return parts.join(',');
}

/// Video filter fragment for a colour preset (empty for [ClipFilter.none]).
String filterFragment(ClipFilter f) {
  switch (f) {
    case ClipFilter.none:
      return '';
    case ClipFilter.mono:
      return 'hue=s=0';
    case ClipFilter.sepia:
      return 'colorchannelmixer='
          '.393:.769:.189:0:.349:.686:.168:0:.272:.534:.131';
    case ClipFilter.warm:
      return 'colorbalance=rs=.10:gs=.02:bs=-.10';
    case ClipFilter.cool:
      return 'colorbalance=rs=-.08:gs=.0:bs=.12';
    case ClipFilter.vivid:
      return 'eq=saturation=1.3:contrast=1.06';
    case ClipFilter.vignette:
      return 'vignette=PI/4';
  }
}

/// Normalisation filter that fits any source onto the target canvas.
String _fit(CanvasPreset canvas) =>
    'scale=${canvas.width}:${canvas.height}:force_original_aspect_ratio=decrease,'
    'pad=${canvas.width}:${canvas.height}:(ow-iw)/2:(oh-ih)/2:color=black,'
    'setsar=1';

/// Full ffmpeg args to render one clip into a normalised intermediate file.
///
/// Every intermediate shares codec, canvas, fps and an audio track, which is
/// what lets the second stage concatenate with `-c copy` (no re-encode).
List<String> buildClipArgs(
  ClipEdit clip,
  CanvasPreset canvas,
  int fps,
  String outputPath,
) {
  final isImage = clip.kind == ClipKind.image;
  final isAudio = clip.kind == ClipKind.audio;
  final window = clip.sourceWindow(3.0);
  final outDur = clip.outputDuration(3.0);

  final args = <String>['-y'];

  // --- inputs -------------------------------------------------------------
  if (isImage) {
    args.addAll(['-loop', '1', '-t', ffSeconds(outDur), '-i', clip.path]);
  } else {
    args.addAll([
      '-ss',
      ffSeconds(clip.trimStart),
      '-t',
      ffSeconds(window),
      '-i',
      clip.path,
    ]);
  }

  var nextInput = 1;
  // Audio-only clips get a synthetic video canvas.
  int? colorInput;
  if (isAudio) {
    args.addAll([
      '-f',
      'lavfi',
      '-t',
      ffSeconds(outDur),
      '-i',
      'color=c=black:s=${canvas.width}x${canvas.height}:r=$fps',
    ]);
    colorInput = nextInput++;
  }
  // Silent audio for images and muted clips, so every part has an audio track.
  int? silenceInput;
  final needSilence = isImage || isAudio || clip.muted;
  if (needSilence) {
    args.addAll([
      '-f',
      'lavfi',
      '-t',
      ffSeconds(outDur),
      '-i',
      'anullsrc=channel_layout=stereo:sample_rate=48000',
    ]);
    silenceInput = nextInput++;
  }

  // --- filter graph -------------------------------------------------------
  final vSrc = isAudio ? '[$colorInput:v]' : '[0:v]';
  final aSrc = (isImage || isAudio || clip.muted)
      ? '[$silenceInput:a]'
      : '[0:a]';

  final vChain = <String>[
    _fit(canvas),
    if (filterFragment(clip.filter).isNotEmpty) filterFragment(clip.filter),
    if (!isImage && clip.speed != 1.0)
      'setpts=${(1 / clip.speed).toStringAsFixed(5)}*PTS',
    'fps=$fps',
  ].join(',');

  final aChain = <String>[
    if (!isImage && !isAudio && clip.speed != 1.0) atempoChain(clip.speed),
    'volume=${clip.muted ? '0' : clip.volume.toStringAsFixed(3)}',
    'aresample=48000',
  ].join(',');

  args.addAll([
    '-filter_complex',
    '$vSrc$vChain[v];$aSrc$aChain[a]',
    '-map',
    '[v]',
    '-map',
    '[a]',
    '-c:v',
    'libx264',
    '-preset',
    'veryfast',
    '-crf',
    '23',
    '-pix_fmt',
    'yuv420p',
    '-r',
    '$fps',
    '-c:a',
    'aac',
    '-b:a',
    '192k',
    '-ar',
    '48000',
    '-movflags',
    '+faststart',
    outputPath,
  ]);
  return args;
}

/// Args to concatenate the normalised intermediates into the final file.
/// [listPath] is a concat-demuxer list file written by the caller.
List<String> buildConcatArgs(String listPath, String outputPath) => <String>[
  '-y',
  '-f',
  'concat',
  '-safe',
  '0',
  '-i',
  listPath,
  '-c',
  'copy',
  '-movflags',
  '+faststart',
  outputPath,
];

/// Body of the concat-demuxer list file. Single quotes in a path are escaped
/// as `'\''` per the demuxer's rules.
String buildConcatList(Iterable<String> partPaths) {
  final buf = StringBuffer();
  for (final p in partPaths) {
    buf.writeln("file '${p.replaceAll("'", r"'\''")}'");
  }
  return buf.toString();
}

/// ffprobe-style duration parse: "12.345000" → 12.345. Null when unusable.
double? parseDuration(String? raw) {
  if (raw == null) return null;
  final v = double.tryParse(raw.trim());
  if (v == null || v <= 0 || v.isNaN || v.isInfinite) return null;
  return v;
}

/// Maps an ffprobe stream `codec_type` to a [ClipKind]. Unknown → video.
ClipKind kindFromStreamType(String? type) {
  switch (type) {
    case 'audio':
      return ClipKind.audio;
    case 'video':
    default:
      return ClipKind.video;
  }
}
