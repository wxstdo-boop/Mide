// Exercises the real GithubUpdater against a fake HTTP transport: only the
// wire is stubbed, the parsing/comparison/asset-selection code is the shipped
// one.
import 'dart:convert';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mide/features/updater/github_updater_io.dart';
import 'package:mide/features/updater/updater_types.dart';
import 'package:cryptography/cryptography.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

const _apk =
    'https://github.com/wxstdo-boop/Mide/releases/download/v1.0.7/'
    'mide-1.0.7-arm64-release.apk';

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.respond);

  final ResponseBody Function(RequestOptions options) respond;
  final List<RequestOptions> seen = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    seen.add(options);
    return respond(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Object body, [int status = 200]) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

GithubUpdater _updater(_FakeAdapter adapter, {String installed = '1.0.6'}) {
  final dio = Dio(BaseOptions(baseUrl: 'https://api.github.com'));
  dio.httpClientAdapter = adapter;
  return GithubUpdater(dio: dio, currentVersion: installed);
}

Map<String, Object?> _release({
  String tag = 'v1.0.7',
  List<Map<String, Object?>>? assets,
}) => {
  'tag_name': tag,
  'html_url': 'https://github.com/wxstdo-boop/Mide/releases/tag/$tag',
  'body': 'Fixed things',
  'published_at': '2026-11-01T10:00:00Z',
  'assets':
      assets ??
      [
        {
          'name': 'mide-1.0.7-arm64-release.apk',
          'browser_download_url': _apk,
          'size': 44094281,
          'digest': 'sha256:${'a' * 64}',
        },
      ],
};

void main() {
  group('checkLatest', () {
    test('reports an available update with its digest', () async {
      final adapter = _FakeAdapter((_) => _json(_release()));
      final res = await _updater(adapter).checkLatest();

      expect(res.kind, UpdateKind.update);
      expect(res.latestVersion, '1.0.7');
      expect(res.asset?.name, 'mide-1.0.7-arm64-release.apk');
      expect(res.asset?.sha256, 'a' * 64);
      expect(res.asset?.sizeMb, '42.1 МБ');
      expect(res.hasUpdate, isTrue);
    });

    test('treats the installed version as up to date', () async {
      final adapter = _FakeAdapter((_) => _json(_release(tag: 'v1.0.6')));
      final res = await _updater(adapter).checkLatest();

      expect(res.kind, UpdateKind.upToDate);
      expect(res.hasUpdate, isFalse);
    });

    test('treats an older release as up to date, never a downgrade', () async {
      final adapter = _FakeAdapter((_) => _json(_release(tag: 'v1.0.5')));
      final res = await _updater(adapter).checkLatest();

      expect(res.kind, UpdateKind.upToDate);
    });

    test('maps 404 to "no releases" instead of an error', () async {
      final adapter = _FakeAdapter((_) => _json({'message': 'Not Found'}, 404));
      final res = await _updater(adapter).checkLatest();

      expect(res.kind, UpdateKind.none);
      expect(res.failed, isFalse);
    });

    test('surfaces a server error as a failure', () async {
      final adapter = _FakeAdapter((_) => _json({'message': 'boom'}, 500));
      final res = await _updater(adapter).checkLatest();

      expect(res.kind, UpdateKind.error);
      expect(res.error, isNotNull);
    });

    test('reports noMatch when the release has no arm64 APK', () async {
      final adapter = _FakeAdapter(
        (_) => _json(
          _release(
            assets: [
              {
                'name': 'mide-1.0.7-windows-x64.exe',
                'browser_download_url':
                    'https://github.com/wxstdo-boop/Mide/x.exe',
              },
            ],
          ),
        ),
      );
      final res = await _updater(adapter).checkLatest();

      expect(res.kind, UpdateKind.noMatch);
      expect(res.latestVersion, '1.0.7');
    });

    test(
      'rejects an empty tag rather than comparing against nothing',
      () async {
        final adapter = _FakeAdapter((_) => _json(_release(tag: '')));
        final res = await _updater(adapter).checkLatest();

        expect(res.kind, UpdateKind.error);
      },
    );

    test('sends a User-Agent GitHub will accept', () async {
      final adapter = _FakeAdapter((_) => _json(_release(tag: 'v1.0.6')));
      await _updater(adapter).checkLatest();

      final headers = adapter.seen.single.headers;
      expect(headers['User-Agent'], 'MideAutoUpdater/1.0');
      expect(headers['Accept'], 'application/vnd.github+json');
    });
  });

  group('downloadAndInstall', () {
    late io.Directory tmp;

    setUp(() {
      tmp = io.Directory.systemTemp.createTempSync('mide_update_test');
      PathProviderPlatform.instance = _FakePathProvider(tmp.path);
    });

    tearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    test('refuses to install when the SHA-256 does not match', () async {
      final adapter = _FakeAdapter(
        (_) => ResponseBody.fromString(
          'not the real bytes',
          200,
          headers: {
            Headers.contentTypeHeader: ['application/octet-stream'],
          },
        ),
      );
      final source = UpdateCheckResult.updateAvailable(
        latestVersion: '1.0.7',
        asset: UpdateAsset(
          name: 'mide-1.0.7-arm64-release.apk',
          url: _apk,
          sizeBytes: 17,
          sha256: 'b' * 64,
        ),
      );

      final res = await _updater(adapter).downloadAndInstall(source);

      expect(res.kind, UpdateKind.error);
      expect(res.error, contains('SHA-256'));
      // A file that failed verification must not be left behind for a user to
      // install by hand.
      expect(
        tmp
            .listSync(recursive: true)
            .whereType<io.File>()
            .where((f) => f.path.endsWith('.apk')),
        isEmpty,
      );
    });

    test('accepts a matching digest and reports progress', () async {
      final bytes = utf8.encode('mide apk bytes');
      final digest = await _sha256Hex(bytes);
      final adapter = _FakeAdapter(
        (_) => ResponseBody.fromBytes(
          bytes,
          200,
          headers: {
            Headers.contentLengthHeader: ['${bytes.length}'],
            Headers.contentTypeHeader: ['application/octet-stream'],
          },
        ),
      );
      final source = UpdateCheckResult.updateAvailable(
        latestVersion: '1.0.7',
        asset: UpdateAsset(
          name: 'mide-1.0.7-arm64-release.apk',
          url: _apk,
          sizeBytes: bytes.length,
          sha256: digest,
        ),
      );
      final progress = <double?>[];

      final res = await _updater(adapter)
          .downloadAndInstall(source, onProgress: progress.add);

      // The host is not Android, so the "installer" path is the desktop
      // launcher; on Linux CI it is xdg-open, which may be absent. What must
      // hold is that verification passed and a real file landed on disk.
      expect(res.kind, isNot(UpdateKind.error), reason: res.error);
      expect(
        tmp
            .listSync(recursive: true)
            .whereType<io.File>()
            .any((f) => f.path.endsWith('mide-1.0.7-arm64-release.apk')),
        isTrue,
      );
      expect(progress, isNotEmpty);
      expect(progress.last, closeTo(1.0, 0.001));
    });

    test('returns the source untouched when there is no asset', () async {
      final adapter = _FakeAdapter((_) => _json({}));
      final source = UpdateCheckResult.upToDate(latestVersion: '1.0.7');

      final res = await _updater(adapter).downloadAndInstall(source);

      expect(res, same(source));
      expect(adapter.seen, isEmpty);
    });
  });
}

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.root);

  final String root;

  @override
  Future<String?> getApplicationSupportPath() async => root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;

  @override
  Future<String?> getDownloadsPath() async => root;

  @override
  Future<String?> getTemporaryPath() async => root;
}

Future<String> _sha256Hex(List<int> bytes) async {
  final hash = await Sha256().hash(bytes);
  return hash.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}
