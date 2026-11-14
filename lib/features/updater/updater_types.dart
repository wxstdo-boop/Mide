// Shared types for the GitHub auto-updater. Platform-free: the io and web
// implementations compile against the same surface.
import 'package:flutter/foundation.dart';

/// A single downloadable asset attached to a GitHub release.
class UpdateAsset {
  const UpdateAsset({
    required this.name,
    required this.url,
    this.sizeBytes = 0,
  });

  final String name;
  final String url;
  final int sizeBytes;

  String get sizeMb {
    final mb = sizeBytes / (1024 * 1024);
    return mb >= 1 ? '${mb.toStringAsFixed(1)} МБ' : '${sizeBytes ~/ 1024} КБ';
  }
}

/// Outcome of a "check for updates" round-trip against
/// `GET /repos/<owner>/<repo>/releases/latest`.
class UpdateCheckResult {
  const UpdateCheckResult._({
    required this.kind,
    this.latestVersion,
    this.asset,
    this.releaseUrl,
    this.notes,
    this.publishedAt,
    this.error,
    this.savedPath,
  });

  factory UpdateCheckResult.upToDate({
    required String latestVersion,
    String? releaseUrl,
    String? notes,
    String? publishedAt,
  }) => UpdateCheckResult._(
    kind: UpdateKind.upToDate,
    latestVersion: latestVersion,
    releaseUrl: releaseUrl,
    notes: notes,
    publishedAt: publishedAt,
  );

  factory UpdateCheckResult.updateAvailable({
    required String latestVersion,
    required UpdateAsset asset,
    String? releaseUrl,
    String? notes,
    String? publishedAt,
  }) => UpdateCheckResult._(
    kind: UpdateKind.update,
    latestVersion: latestVersion,
    asset: asset,
    releaseUrl: releaseUrl,
    notes: notes,
    publishedAt: publishedAt,
  );

  factory UpdateCheckResult.noReleases() =>
      const UpdateCheckResult._(kind: UpdateKind.none);

  /// Newer release exists but ships no asset for the current platform.
  factory UpdateCheckResult.noMatchingAsset({
    required String latestVersion,
    String? releaseUrl,
    String? notes,
    String? publishedAt,
  }) => UpdateCheckResult._(
    kind: UpdateKind.noMatch,
    latestVersion: latestVersion,
    releaseUrl: releaseUrl,
    notes: notes,
    publishedAt: publishedAt,
  );

  factory UpdateCheckResult.failure(String error) =>
      UpdateCheckResult._(kind: UpdateKind.error, error: error);

  factory UpdateCheckResult.installerOpened(
    UpdateCheckResult source,
    String path,
  ) => UpdateCheckResult._(
    kind: UpdateKind.installerOpened,
    latestVersion: source.latestVersion,
    asset: source.asset,
    releaseUrl: source.releaseUrl,
    notes: source.notes,
    publishedAt: source.publishedAt,
    error: source.error,
    savedPath: path,
  );

  final UpdateKind kind;
  final String? latestVersion;
  final UpdateAsset? asset;
  final String? releaseUrl;
  final String? notes;
  final String? publishedAt;
  final String? error;
  final String? savedPath;

  bool get hasUpdate => kind == UpdateKind.update && asset != null;
  bool get failed => kind == UpdateKind.error;
  bool get none => kind == UpdateKind.none;
}

enum UpdateKind { update, upToDate, none, noMatch, error, installerOpened }

/// Compares numeric release versions, ignoring a leading `v` and build metadata.
/// Returns null when either input is not a dotted numeric version.
int? compareVersions(String left, String right) {
  final pattern = RegExp(r'^v?(\d+(?:\.\d+)*)(?:[-+].*)?$');
  final leftMatch = pattern.firstMatch(left.trim());
  final rightMatch = pattern.firstMatch(right.trim());
  if (leftMatch == null || rightMatch == null) return null;

  final leftParts = leftMatch.group(1)!.split('.').map(int.parse).toList();
  final rightParts = rightMatch.group(1)!.split('.').map(int.parse).toList();
  final length = leftParts.length > rightParts.length
      ? leftParts.length
      : rightParts.length;
  for (var i = 0; i < length; i++) {
    final leftPart = i < leftParts.length ? leftParts[i] : 0;
    final rightPart = i < rightParts.length ? rightParts[i] : 0;
    if (leftPart != rightPart) return leftPart.compareTo(rightPart);
  }
  return 0;
}

UpdateAsset? androidArm64ApkFrom(List<dynamic> rawAssets) {
  for (final item in rawAssets.whereType<Map>()) {
    final name = (item['name'] ?? '').toString();
    final url = (item['browser_download_url'] ?? '').toString();
    final uri = Uri.tryParse(url);
    final lowerName = name.toLowerCase();
    if (!lowerName.startsWith('mide-') ||
        !lowerName.contains('arm64') ||
        !lowerName.endsWith('.apk') ||
        uri == null ||
        uri.scheme != 'https' ||
        uri.host != 'github.com') {
      continue;
    }
    return UpdateAsset(
      name: name,
      url: url,
      sizeBytes: int.tryParse((item['size'] ?? '0').toString()) ?? 0,
    );
  }
  return null;
}

/// Best-effort "what platform am I on" label, used to pick a release asset
/// whose filename matches (e.g. `mide-windows-x64.exe`).
String get currentPlatformTag {
  if (kIsWeb) return 'web';
  switch (defaultTargetPlatform) {
    case TargetPlatform.windows:
      return 'windows';
    case TargetPlatform.linux:
      return 'linux';
    case TargetPlatform.macOS:
      return 'macos';
    case TargetPlatform.android:
      return 'android';
    case TargetPlatform.iOS:
      return 'ios';
    default:
      return 'unknown';
  }
}
