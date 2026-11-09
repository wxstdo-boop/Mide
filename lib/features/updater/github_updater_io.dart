// Real (VM/desktop/mobile) GitHub auto-updater.
//
// * check:    GET /repos/<owner>/<repo>/releases/latest
// * download: dio streaming download into the OS downloads dir
// * launch:   native installer (.exe/.msi/.dmg/.deb) opened via the OS;
//             on Android the .apk is opened with an ACTION_VIEW intent.
//
// The web build gets [github_updater_web] instead (check still works;
// "install" degrades to "open the release page in a browser").
import 'dart:io' as io;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'github_config.dart';
import 'updater_types.dart';

class GithubUpdater {
  const GithubUpdater({this.dio});

  /// Injectable for tests; a default is created otherwise.
  final Dio? dio;

  static Dio _makeDefault() => Dio(BaseOptions(
        baseUrl: 'https://api.github.com',
        receiveDataWhenStatusError: true,
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 60),
        sendTimeout: const Duration(seconds: 20),
      ));

  Dio get _client => dio ?? _makeDefault();

  /// Update check: never needs a token for the public repo.
  Future<UpdateCheckResult> checkLatest() async {
    final client = _client;
    client.options.headers['User-Agent'] = 'MideAutoUpdater/1.0';
    client.options.headers['Accept'] = 'application/vnd.github+json';

    try {
      final res = await client.get('/repos/${GithubConfig.path}/releases/latest');
      final data = res.data;
      if (data is! Map) {
        return UpdateCheckResult.failure('Неожиданный ответ GitHub API');
      }
      final tag = (data['tag_name'] ?? '').toString().trim();
      if (tag.isEmpty) return UpdateCheckResult.failure('GitHub: пустая версия');

      final htmlUrl = (data['html_url'] ?? '').toString();
      final body = (data['body'] ?? '').toString();
      final publishedAt = (data['published_at'] ?? '').toString();
      final prerelease = data['prerelease'] == true;

      final asset = _pickAsset((data['assets'] ?? const []) as List, prerelease);
      if (asset == null) {
        return UpdateCheckResult.noMatchingAsset(
          latestVersion: _stripV(tag),
          releaseUrl: htmlUrl,
          notes: body.isEmpty ? null : body,
          publishedAt: publishedAt.isEmpty ? null : publishedAt,
        );
      }
      return UpdateCheckResult.updateAvailable(
        latestVersion: _stripV(tag),
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
          msg.isNotEmpty ? msg : 'Нет соединения с GitHub');
    }
  }

  /// Download [asset] to the OS downloads dir and launch the installer.
  /// On Android this opens the system "do you want to install?" dialog.
  /// Returns [UpdateCheckResult.installed] with the saved path.
  Future<UpdateCheckResult> downloadAndInstall(UpdateCheckResult source) async {
    final asset = source.asset;
    if (asset == null) return source;

    final dir = await _downloadsDir();
    final safe = asset.name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final target = '$dir${io.Platform.pathSeparator}$safe';

    await _client.download(asset.url, target, deleteOnError: true);

    if (!io.File(target).existsSync()) {
      return UpdateCheckResult.failure('Файл не сохранился');
    }

    await _launch(target, asset.name);
    return UpdateCheckResult.installed(source, target);
  }

  /// Web / unsupported: just open the release page.
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
    if (io.Platform.isAndroid || io.Platform.isIOS) {
      // Application downloads dir; the install dialog picks it up.
      final app = await getApplicationDocumentsDirectory();
      final d = io.Directory('${app.path}/downloads')..createSync(recursive: true);
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
        await _runOr('gdebi', [path], fallback: io.Process.run('sudo', ['dpkg', '-i', path]));
      } else if (lower.endsWith('.rpm')) {
        await io.Process.run('sudo', ['rpm', '-i', path]);
      } else {
        await io.Process.start('xdg-open', [path]);
      }
    } else {
      // Android: open with ACTION_VIEW → the install dialog.
      // url_launcher handles the intent routing.
      await launchUrl(Uri.file(path));
    }
  }

  Future<void> _runOr(String bin, List<String> args,
      {required Future<io.ProcessResult> fallback}) async {
    try {
      await io.Process.run(bin, args);
    } catch (_) {
      await fallback;
    }
  }

  /// Pick the asset matching the current platform by filename hint.
  UpdateAsset? _pickAsset(List<dynamic> rawAssets, bool prerelease) {
    if (rawAssets.isEmpty) return null;
    final assets = rawAssets
        .whereType<Map>()
        .map((m) => UpdateAsset(
              name: (m['name'] ?? '').toString(),
              url: (m['browser_download_url'] ?? '').toString(),
              sizeBytes: int.tryParse((m['size'] ?? '0').toString()) ?? 0,
            ))
        .toList();
    if (assets.isEmpty) return null;

    const wanted = switch (currentPlatformTag) {
      'windows' => ['Windows', '.exe', '.msi'],
      'macos' => ['mac', '.dmg', '.pkg'],
      'linux' => ['Linux', '.deb', '.AppImage', '.rpm', '.tar.gz'],
      'android' => ['Android', '.apk'],
      'ios' => ['iOS', '.ipa'],
      'web' => ['web', '.html'],
      _ => const [
          'Windows', '.exe', '.msi',
          'mac', '.dmg', '.pkg',
          'Linux', '.deb',
        ],
    };

    // Strongest match: filename contains the platform keyword AND extension.
    for (final a in assets) {
      final n = a.name.toLowerCase();
      if (n.contains(wanted[0].toLowerCase()) &&
          (n.contains(wanted[1].toLowerCase()) ||
              (wanted.length > 2 && n.contains(wanted[2].toLowerCase())))) {
        return a;
      }
    }
    // Extension-only match.
    for (final a in assets) {
      final n = a.name.toLowerCase();
      for (var i = 1; i < wanted.length; i++) {
        if (n.endsWith(wanted[i].toLowerCase())) return a;
      }
    }
    // Prereleases can carry fewer assets — fall back to the first one.
    if (prerelease) return assets.first;
    return assets.first;
  }

  String _stripV(String tag) =>
      tag.toLowerCase().startsWith('v') ? tag.substring(1) : tag;
}
