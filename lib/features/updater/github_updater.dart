// Public facade for the GitHub auto-updater.
//
// Conditional import: VM / desktop / mobile builds pull in the full
// implementation (github_updater_io.dart) that downloads the release asset
// and launches the installer. Web builds pull in the stub
// (github_updater_web.dart) where "install" degrades to opening the release
// page in a browser — the plain dio check still works identically.
import 'github_updater_io.dart'
    if (dart.library.js_interop) 'github_updater_web.dart';

/// The active [GithubUpdater] for the current platform. On web the same class
/// name resolves to the web stub; `checkLatest()` works in both.
const GithubUpdater githubUpdater = GithubUpdater();
