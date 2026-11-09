// Web stub for the GitHub auto-updater. The *check* works the same as on
// VM (plain dio against the public GitHub API, no token needed), but a web
// app cannot launch a local installer — "install" opens the asset / release
// page in the browser instead.
import 'package:dio/dio.dart';
import 'package:url_launcher/url_launcher.dart';

import 'github_config.dart';
import 'updater_types.dart';

class GithubUpdater {
  const GithubUpdater({this.dio});

  final Dio? dio;

  static Dio _makeDefault() => Dio(BaseOptions(
        baseUrl: 'https://api.github.com',
        receiveDataWhenStatusError: true,
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 60),
      ));

  Dio get _client => dio ?? _makeDefault();

  Future<UpdateCheckResult> checkLatest() async {
    final client = _client;
    client.options.headers['User-Agent'] = 'MideAutoUpdater/1.0';
    client.options.headers['Accept'] = 'application/vnd.github+json';
    try {
      final res =
          await client.get('/repos/${GithubConfig.path}/releases/latest');
      final data = res.data;
      if (data is! Map) {
        return UpdateCheckResult.failure('Неожиданный ответ GitHub API');
      }
      final tag = (data['tag_name'] ?? '').toString().trim();
      if (tag.isEmpty) return UpdateCheckResult.failure('GitHub: пустая версия');

      final htmlUrl = (data['html_url'] ?? '').toString();
      final body = (data['body'] ?? '').toString();
      final publishedAt = (data['published_at'] ?? '').toString();

      final assets = ((data['assets'] ?? const []) as List)
          .whereType<Map>()
          .map((m) => UpdateAsset(
                name: (m['name'] ?? '').toString(),
                url: (m['browser_download_url'] ?? '').toString(),
                sizeBytes: int.tryParse((m['size'] ?? '0').toString()) ?? 0,
              ))
          .toList();
      if (assets.isEmpty) return UpdateCheckResult.noReleases();

      return UpdateCheckResult.updateAvailable(
        latestVersion: _stripV(tag),
        asset: assets.first,
        releaseUrl: htmlUrl,
        notes: body.isEmpty ? null : body,
        publishedAt: publishedAt.isEmpty ? null : publishedAt,
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return UpdateCheckResult.noReleases();
      final msg = e.message ?? '';
      return UpdateCheckResult.failure(
          msg.isNotEmpty ? msg : 'Нет соединения с GitHub');
    }
  }

  /// Web: "install" = open the asset URL in the browser (it downloads).
  Future<UpdateCheckResult> downloadAndInstall(UpdateCheckResult source) async {
    final asset = source.asset;
    if (asset == null) return source;
    await openReleasePage(source);
    return UpdateCheckResult.installed(source, 'browser:${asset.url}');
  }

  Future<void> openReleasePage(UpdateCheckResult result) async {
    final url = result.releaseUrl ?? GithubConfig.releasesPage;
    try {
      // Opens in the system browser on web (new tab), native browser elsewhere.
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      // No browser available — the user can open the link manually.
    }
  }
}

String _stripV(String tag) =>
    tag.toLowerCase().startsWith('v') ? tag.substring(1) : tag;
