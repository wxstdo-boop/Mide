// Pure FFmpeg command builders + the Clip Studio project notifier.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mide/features/clip/clip_ffmpeg.dart';
import 'package:mide/features/clip/clip_models.dart';
import 'package:mide/features/clip/clip_providers.dart';

void main() {
  group('ffSeconds', () {
    test('trims trailing zeros', () {
      expect(ffSeconds(1.5), '1.5');
      expect(ffSeconds(2.0), '2');
      expect(ffSeconds(0), '0');
      expect(ffSeconds(1.23456), '1.235');
    });
  });

  group('atempoChain', () {
    test('passes through in-range speeds', () {
      expect(atempoChain(1.5), 'atempo=1.5000');
    });

    test('halves the chain above 2x', () {
      expect(atempoChain(4.0), 'atempo=2.0,atempo=2.0000');
      expect(atempoChain(3.0), 'atempo=2.0,atempo=1.5000');
    });

    test('doubles the chain below 0.5x', () {
      expect(atempoChain(0.25), 'atempo=0.5,atempo=0.5000');
    });
  });

  group('filterFragment', () {
    test('none is empty, others are non-empty', () {
      expect(filterFragment(ClipFilter.none), isEmpty);
      for (final f in ClipFilter.values) {
        if (f == ClipFilter.none) continue;
        expect(filterFragment(f), isNotEmpty, reason: f.name);
      }
    });
  });

  group('buildClipArgs', () {
    const canvas = CanvasPreset.vertical9x16;

    test('video: trims, fits and maps audio', () {
      const clip = ClipEdit(
        path: '/v/a.mp4',
        name: 'a.mp4',
        kind: ClipKind.video,
        duration: 10,
        trimStart: 2,
        trimEnd: 6,
        speed: 2.0,
        volume: 0.5,
      );
      final args = buildClipArgs(clip, canvas, 30, '/out/p.mp4');
      expect(args, contains('-ss'));
      expect(args, containsAllInOrder(['-ss', '2', '-t', '4']));
      expect(args, containsAllInOrder(['-i', '/v/a.mp4']));
      final fc = args[args.indexOf('-filter_complex') + 1];
      expect(fc, contains('scale=1080:1920'));
      expect(fc, contains('setpts=0.50000*PTS'));
      expect(fc, contains('atempo=2.0000'));
      expect(fc, contains('volume=0.500'));
      expect(args.last, '/out/p.mp4');
    });

    test('image: loops, gets silent audio, no atempo', () {
      const clip = ClipEdit(
        path: '/i/a.png',
        name: 'a.png',
        kind: ClipKind.image,
        duration: 3,
      );
      final args = buildClipArgs(clip, canvas, 30, '/out/p.mp4');
      expect(args, containsAllInOrder(['-loop', '1']));
      expect(
        args,
        contains('anullsrc=channel_layout=stereo:sample_rate=48000'),
      );
      final fc = args[args.indexOf('-filter_complex') + 1];
      expect(fc, isNot(contains('atempo')));
    });

    test('muted video: volume forced to 0', () {
      const clip = ClipEdit(
        path: '/v/a.mp4',
        name: 'a.mp4',
        kind: ClipKind.video,
        duration: 5,
        muted: true,
      );
      final args = buildClipArgs(clip, canvas, 30, '/out/p.mp4');
      final fc = args[args.indexOf('-filter_complex') + 1];
      expect(fc, contains('volume=0'));
    });

    test('audio: adds a black video canvas', () {
      const clip = ClipEdit(
        path: '/m/a.mp3',
        name: 'a.mp3',
        kind: ClipKind.audio,
        duration: 8,
      );
      final args = buildClipArgs(clip, canvas, 30, '/out/p.mp4');
      expect(args, contains('color=c=black:s=1080x1920:r=30'));
    });
  });

  group('buildConcatArgs / buildConcatList', () {
    test('copy concat args', () {
      final args = buildConcatArgs('/tmp/list.txt', '/out/final.mp4');
      expect(args, containsAllInOrder(['-f', 'concat']));
      expect(args, contains('copy'));
      expect(args.last, '/out/final.mp4');
    });

    test('escapes single quotes in the list', () {
      final list = buildConcatList(['/tmp/a b.mp4', "/tmp/o'brien.mp4"]);
      expect(list, contains("file '/tmp/a b.mp4'"));
      expect(list, contains(r"file '/tmp/o'\''brien.mp4'"));
    });
  });

  group('parseDuration', () {
    test('accepts positive numbers, rejects junk', () {
      expect(parseDuration('12.345'), 12.345);
      expect(parseDuration(' 3 '), 3);
      expect(parseDuration('0'), isNull);
      expect(parseDuration('-1'), isNull);
      expect(parseDuration('abc'), isNull);
      expect(parseDuration(null), isNull);
    });
  });

  group('ClipEdit timing', () {
    test('outputDuration applies trim then speed', () {
      const clip = ClipEdit(
        path: 'x',
        name: 'x',
        kind: ClipKind.video,
        duration: 10,
        trimStart: 2,
        trimEnd: 8,
        speed: 2.0,
      );
      expect(clip.sourceWindow(3), 6);
      expect(clip.outputDuration(3), 3);
    });

    test('image duration ignores speed', () {
      const clip = ClipEdit(
        path: 'x',
        name: 'x',
        kind: ClipKind.image,
        duration: 4,
        speed: 3.0,
      );
      expect(clip.outputDuration(3), 4);
    });
  });

  group('ClipProjectNotifier', () {
    ProviderContainer make() => ProviderContainer();

    ClipEdit clip(String p) =>
        ClipEdit(path: p, name: p, kind: ClipKind.video, duration: 5);

    test('add / reorder / remove / duplicate', () {
      final c = make();
      final n = c.read(clipProjectProvider.notifier);
      n.addClips([clip('a'), clip('b'), clip('c')]);
      expect(c.read(clipProjectProvider).clips.map((e) => e.path), [
        'a',
        'b',
        'c',
      ]);

      n.reorder(0, 3); // ReorderableListView order: move a to the end
      expect(c.read(clipProjectProvider).clips.map((e) => e.path), [
        'b',
        'c',
        'a',
      ]);

      n.moveTo(0, 2); // already-adjusted target index: move b to the end
      expect(c.read(clipProjectProvider).clips.map((e) => e.path), [
        'c',
        'a',
        'b',
      ]);

      n.duplicateAt(0);
      expect(c.read(clipProjectProvider).clips.length, 4);
      expect(c.read(clipProjectProvider).clips[1].path, 'c');

      n.removeAt(0);
      expect(c.read(clipProjectProvider).clips.map((e) => e.path), [
        'c',
        'a',
        'b',
      ]);

      n.clear();
      expect(c.read(clipProjectProvider).isEmpty, isTrue);
    });

    test('totalDuration sums trimmed lengths', () {
      final c = make();
      final n = c.read(clipProjectProvider.notifier);
      n.addClips([
        const ClipEdit(
          path: 'a',
          name: 'a',
          kind: ClipKind.video,
          duration: 10,
          trimStart: 0,
          trimEnd: 4,
        ),
        const ClipEdit(
          path: 'b',
          name: 'b',
          kind: ClipKind.video,
          duration: 10,
          trimStart: 0,
          trimEnd: 8,
          speed: 2.0,
        ),
      ]);
      expect(c.read(clipProjectProvider).totalDuration, 8);
    });

    test('setCanvas / setFps', () {
      final c = make();
      final n = c.read(clipProjectProvider.notifier);
      n.setCanvas(CanvasPreset.square1x1);
      n.setFps(60);
      final p = c.read(clipProjectProvider);
      expect(p.canvas, CanvasPreset.square1x1);
      expect(p.fps, 60);
    });
  });

  group('ClipExportNotifier', () {
    test('empty project fails fast without touching the engine', () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await c.read(clipExportProvider.notifier).run(const ClipProject());
      final s = c.read(clipExportProvider);
      expect(s.phase, ExportPhase.failed);
      expect(s.message, contains('клип'));
      expect(s.busy, isFalse);
    });
  });
}
