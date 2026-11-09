// Public GitHub target for the in-app auto-updater (Settings → Обновления).
// Repo is public: the update *check* needs no token. The PAT that ships the
// releases lives in GitHub Actions secrets, not in this file.
class GithubConfig {
  static const String owner = 'wxstdo-boop';
  static const String repo = 'Mide';

  static String get path => '$owner/$repo';

  static String get releasesPage =>
      'https://github.com/$owner/$repo/releases';
}
