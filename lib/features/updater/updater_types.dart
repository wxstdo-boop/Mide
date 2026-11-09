// Shared types for the GitHub auto-updater. Platform-free: the io and web
// implementations compile against the same surface.
import 'package:flutter/foundation.dart';

/// A single downloadable asset attached to a GitHub release.
class UpdateAsset {
  const UpdateAsset({required this.name, required this.url, this.sizeBytes = 0});

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
  }) =>
      UpdateCheckResult._(
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
  }) =>
      UpdateCheckResult._(
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
  }) =>
      UpdateCheckResult._(
        kind: UpdateKind.noMatch,
        latestVersion: latestVersion,
        releaseUrl: releaseUrl,
        notes: notes,
        publishedAt: publishedAt,
      );

  factory UpdateCheckResult.failure(String error) =>
      UpdateCheckResult._(kind: UpdateKind.error, error: error);

  factory UpdateCheckResult.installed(UpdateCheckResult source, String path) =>
      UpdateCheckResult._(
        kind: source.kind,
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

enum UpdateKind { update, upToDate, none, noMatch, error, installed }

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
