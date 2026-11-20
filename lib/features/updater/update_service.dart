// Platform-free seam for the auto-updater so the Settings section can be
// driven by a fake in tests. The real implementations (io / web) live behind
// github_updater.dart and both satisfy this interface.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'github_updater.dart';
import 'updater_types.dart';

abstract class UpdateService {
  Future<UpdateCheckResult> checkLatest();

  Future<UpdateCheckResult> downloadAndInstall(
    UpdateCheckResult source, {
    void Function(double? progress)? onProgress,
  });

  Future<void> openReleasePage(UpdateCheckResult result);
}

/// Overridden in tests with a fake so no network or platform channel is hit.
final updateServiceProvider = Provider<UpdateService>((ref) => githubUpdater);
