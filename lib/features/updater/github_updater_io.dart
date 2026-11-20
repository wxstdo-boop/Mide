// Native GitHub updater. The current release pipeline publishes Android arm64.
//
// * check:    GET /repos/<owner>/<repo>/releases/latest
// * download: dio streaming download into the OS downloads dir
// * launch:   opens the downloaded APK in Android's system installer.
import 'dart:io' as io;

import 'package:cryptography/cryptography.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'github_config.dart';
import 'update_service.dart';
import 'updater_types.dart';

class GithubUpdater implements UpdateService {
  const GithubUpdater({this.dio, this.currentVersion});

  /// Injectable for tests; a default is created otherwise.
  final Dio? dio;

  /// Installed app version. Resolved from the real package metadata when not
  /// injected, so the updater never compares against a stale constant.
  final String? currentVersion;

  static const MethodChannel _installerChannel = MethodChannel(
    'mide/update_installer',
  );

  static Dio _makeDefault() => Dio(
    BaseOptions(
      baseUrl: 'https://api.github.com',
      receiveDataWhenStatusError: true,
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 60),
      sendTimeout: const Duration(seconds: 20),
    ),
  );

  Dio get _client => dio ?? _makeDefault();

  /// Update check: never needs a token for the public repo.
  @override
  Future<UpdateCheckResult> checkLatest() async {
    final client = _client;
    client.options.headers['User-Agent'] = 'MideAutoUpdater/1.0';
    client.options.headers['Accept'] = 'application/vnd.github+json';

    try {
      final res = await client.get(
        '/repos/${GithubConfig.path}/releases/latest',
      );
      final data = res.data;
      if (data is! Map) {
        return UpdateCheckResult.failure('Неожиданный ответ GitHub API');
      }
      final tag = (data['tag_name'] ?? '').toString().trim();
      if (tag.isEmpty) {
        return UpdateCheckResult.failure('GitHub: пустая версия');
      }

      final htmlUrl = (data['html_url'] ?? '').toString();
      final body = (data['body'] ?? '').toString();
      final publishedAt = (data['published_at'] ?? '').toString();
      final version = _stripV(tag);
      final installed =
          currentVersion ?? await GithubConfig.resolveCurrentVersion();
      final comparison = compareVersions(version, installed);
      if (comparison == null) {
        return UpdateCheckResult.failure(
          'Не удалось сравнить версии $installed и $version',
        );
      }
      if (comparison <= 0) {
        return UpdateCheckResult.upToDate(
          latestVersion: version,
          releaseUrl: htmlUrl,
          notes: body.isEmpty ? null : body,
          publishedAt: publishedAt.isEmpty ? null : publishedAt,
        );
      }

      final rawAssets = data['assets'];
      if (rawAssets is! List) {
        return UpdateCheckResult.failure('В релизе отсутствует список файлов');
      }
      final asset = androidArm64ApkFrom(rawAssets);
      if (asset == null) {
        return UpdateCheckResult.noMatchingAsset(
          latestVersion: version,
          releaseUrl: htmlUrl,
          notes: body.isEmpty ? null : body,
          publishedAt: publishedAt.isEmpty ? null : publishedAt,
        );
      }
      return UpdateCheckResult.updateAvailable(
        latestVersion: version,
        asset: asset,
        releaseUrl: htmlUrl,
        notes: body.isEmpty ? null : body,
        publishedAt: publishedAt.isEmpty ? null : publishedAt,
      );
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == 404) return UpdateCheckResult.noReleases();
      final msg = e.message ?? '';
      return UpdateCheckResult.failure(
        msg.isNotEmpty ? msg : 'Нет соединения с GitHub',
      );
    }
  }

  /// Download [asset] to the OS downloads dir and launch the installer.
  /// [onProgress] reports 0..1 while the bytes arrive (null when the server
  /// sends no Content-Length).
  @override
  Future<UpdateCheckResult> downloadAndInstall(
    UpdateCheckResult source, {
    void Function(double? progress)? onProgress,
  }) async {
    final asset = source.asset;
    if (asset == null) return source;

    final dir = await _downloadsDir();
    final safe = asset.name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final target = '$dir${io.Platform.pathSeparator}$safe';

    await _client.download(
      asset.url,
      target,
      deleteOnError: true,
      onReceiveProgress: onProgress == null
          ? null
          : (received, total) {
              if (total > 0) {
                onProgress(received / total);
              } else if (asset.sizeBytes > 0) {
                onProgress((received / asset.sizeBytes).clamp(0.0, 1.0));
              } else {
                onProgress(null);
              }
            },
    );

    if (!io.File(target).existsSync()) {
      return UpdateCheckResult.failure('Файл не сохранился');
    }

    if (!await _verifyDigest(asset, target)) {
      try {
        io.File(target).deleteSync();
      } catch (_) {}
      return UpdateCheckResult.failure(
        'Проверка SHA-256 не прошла — файл повреждён или подменён',
      );
    }

    if (io.Platform.isAndroid && asset.name.toLowerCase().endsWith('.apk')) {
      try {
        await _installerChannel.invokeMethod<void>('installApk', {
          'path': target,
        });
      } on PlatformException catch (e) {
        // The native side refuses to install an APK it cannot verify; surface
        // that as the user-facing reason instead of a raw platform error.
        final reason = switch (e.code) {
          'signature_mismatch' =>
            'APK подписан другим ключом — обновление отменено',
          'signature_unreadable' =>
            'Подпись APK не читается — обновление отменено',
          'missing_apk' => 'Скачанный APK не найден — попробуй ещё раз',
          'invalid_path' => 'Некорректный путь к APK',
          _ => 'Установщик не открылся: ${e.message ?? e.code}',
        };
        return UpdateCheckResult.failure(reason);
      }
    } else {
      await _launch(target, asset.name);
    }
    return UpdateCheckResult.installerOpened(source, target);
  }

  /// Verifies the downloaded file against the release's published SHA-256.
  /// When the release carries no digest we cannot verify, so we allow it
  /// (older releases) rather than blocking updates; a mismatching digest is
  /// always fatal.
  Future<bool> _verifyDigest(UpdateAsset asset, String path) async {
    final expected = asset.sha256;
    if (expected == null) return true;
    final actual = await _sha256OfFile(path);
    return actual == expected;
  }

  static Future<String> _sha256OfFile(String path) async {
    final sink = Sha256().newHashSink();
    await io.File(path).openRead().forEach(sink.add);
    sink.close();
    final digest = await sink.hash();
    return digest.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Web / unsupported: just open the release page.
  @override
  Future<void> openReleasePage(UpdateCheckResult result) async {
    final url = result.releaseUrl ?? GithubConfig.releasesPage;
    final uri = Uri.parse(url);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // Web without a browser: ignore.
    }
  }

  // ── Internals ─────────────────────────────────────────────────────────────

  Future<String> _downloadsDir() async {
    if (io.Platform.isAndroid) {
      // Must live under the FileProvider `files-path` root, otherwise
      // `FileProvider.getUriForFile` throws "Failed to find configured root"
      // and the install dialog never opens.
      final app = await getApplicationSupportDirectory();
      final d = io.Directory('${app.path}/downloads')
        ..createSync(recursive: true);
      return d.path;
    }
    if (io.Platform.isIOS) {
      final app = await getApplicationDocumentsDirectory();
      final d = io.Directory('${app.path}/downloads')
        ..createSync(recursive: true);
      return d.path;
    }
    return (await getDownloadsDirectory())?.path ??
        (await getApplicationDocumentsDirectory()).path;
  }

  Future<void> _launch(String path, String fileName) async {
    final lower = fileName.toLowerCase();
    if (io.Platform.isWindows) {
      // ShellExec shows the "how do you want to open?" prompt for unknown types.
      await io.Process.start('rundll32', ['shell32.dll,ShellExec', path]);
    } else if (io.Platform.isMacOS) {
      await io.Process.start('open', [path]);
    } else if (io.Platform.isLinux) {
      if (lower.endsWith('.deb')) {
        await _runOr('gdebi', [
          path,
        ], fallback: io.Process.run('sudo', ['dpkg', '-i', path]));
      } else if (lower.endsWith('.rpm')) {
        await io.Process.run('sudo', ['rpm', '-i', path]);
      } else {
        await io.Process.start('xdg-open', [path]);
      }
    } else {
      throw UnsupportedError('No installer is available for $fileName');
    }
  }

  Future<void> _runOr(
    String bin,
    List<String> args, {
    required Future<io.ProcessResult> fallback,
  }) async {
    try {
      await io.Process.run(bin, args);
    } catch (_) {
      await fallback;
    }
  }

  String _stripV(String tag) =>
      tag.toLowerCase().startsWith('v') ? tag.substring(1) : tag;
}
