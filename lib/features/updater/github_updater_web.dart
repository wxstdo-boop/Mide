// Web stub for the GitHub auto-updater. The *check* works the same as on
// VM (plain dio against the public GitHub API, no token needed). The current
// release pipeline publishes Android-only assets, so web reports no matching
// update rather than downloading an incompatible APK.
import 'package:dio/dio.dart';
import 'package:url_launcher/url_launcher.dart';

import 'github_config.dart';
import 'updater_types.dart';

class GithubUpdater {
  const GithubUpdater({
    this.dio,
    this.currentVersion = GithubConfig.currentVersion,
  });

  final Dio? dio;
  final String currentVersion;

  static Dio _makeDefault() => Dio(
    BaseOptions(
      baseUrl: 'https://api.github.com',
      receiveDataWhenStatusError: true,
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 60),
    ),
  );

  Dio get _client => dio ?? _makeDefault();

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
      final comparison = compareVersions(version, currentVersion);
      if (comparison == null) {
        return UpdateCheckResult.failure(
          'Не удалось сравнить версии $currentVersion и $version',
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
      if (e.response?.statusCode == 404) return UpdateCheckResult.noReleases();
      final msg = e.message ?? '';
      return UpdateCheckResult.failure(
        msg.isNotEmpty ? msg : 'Нет соединения с GitHub',
      );
    }
  }

  /// Web cannot install an APK and currently has no matching release asset.
  Future<UpdateCheckResult> downloadAndInstall(UpdateCheckResult source) async {
    final asset = source.asset;
    if (asset == null) return source;
    await openReleasePage(source);
    return UpdateCheckResult.installerOpened(source, 'browser:${asset.url}');
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
