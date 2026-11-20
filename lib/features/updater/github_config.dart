// Public GitHub target for the in-app auto-updater (Settings → Обновления).
// Repo is public: the update *check* needs no token. The PAT that ships the
// releases lives in GitHub Actions secrets, not in this file.
import 'package:package_info_plus/package_info_plus.dart';

class GithubConfig {
  static const String owner = 'wxstdo-boop';
  static const String repo = 'Mide';

  /// Compile-time override, used by release builds so the version is known
  /// before the first frame. Falls back to the real package version at
  /// runtime (see [resolveCurrentVersion]) when the define is absent, so a
  /// locally built APK does not silently claim to be 1.0.1 forever.
  static const String _compileTimeVersion = String.fromEnvironment(
    'APP_VERSION',
  );

  /// Legacy synchronous accessor. Prefer [resolveCurrentVersion]: this returns
  /// the compile-time define, or the pubspec version baked into the bundle
  /// when the define is missing (which is what `String.fromEnvironment`
  /// cannot do on its own).
  static String get currentVersion =>
      _compileTimeVersion.isNotEmpty ? _compileTimeVersion : fallbackVersion;

  /// Version from `pubspec.yaml`, generated into the app at build time by
  /// Flutter as the Android/iOS versionName. Kept as a static so tests can
  /// exercise the comparison without a platform channel.
  static const String fallbackVersion = '1.0.11';

  static Future<String> resolveCurrentVersion() async {
    if (_compileTimeVersion.isNotEmpty) return _compileTimeVersion;
    try {
      final info = await PackageInfo.fromPlatform();
      if (info.version.isNotEmpty) return info.version;
    } catch (_) {
      // Platform channel unavailable (unit tests / unsupported platform).
    }
    return fallbackVersion;
  }

  static String get path => '$owner/$repo';

  static String get releasesPage => 'https://github.com/$owner/$repo/releases';
}
