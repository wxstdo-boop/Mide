// Active tab (0 = CRY, 1 = NPV, 2 = MEarn) — persisted so the app reopens
// where you left off. 3D and Clip used to be tabs 3 and 4; a value persisted
// by an older build is clamped onto NPV rather than leaving the shell blank. The persisted value is resolved
// synchronously up-front (see [AppTabNotifier.loadPersisted]) and handed to
// the notifier as a seed, so the very first frame already shows the
// last-opened tab instead of flashing NPV and then jumping.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AppTabNotifier extends Notifier<int> {
  /// Number of top-level tabs. Kept in sync with the pill bar in shell.dart.
  static const int tabCount = 3;

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const _key = 'mide_active_tab';
  static const _default = 1; // NPV (VPN)

  /// Old builds persisted 3 (3D) and 4 (Clip), which no longer exist.
  static int _sanitize(int value) =>
      value >= 0 && value < tabCount ? value : _default;

  /// Read the persisted tab off the main isolate *before* the first frame.
  /// Call [WidgetsFlutterBinding.ensureInitialized] first. Falls back to
  /// [_default] on any read failure so launch never blocks on storage.
  static Future<int> loadPersisted() async {
    try {
      final raw = await _storage.read(key: _key);
      final v = int.tryParse(raw ?? '');
      if (v != null) return _sanitize(v);
    } catch (_) {
      // Non-fatal.
    }
    return _default;
  }

  bool _userChose = false;
  final int? _seed;

  AppTabNotifier({int? seed}) : _seed = seed, _userChose = seed != null {
    // A non-null seed already reflects the persisted choice.
  }

  @override
  int build() {
    final seed = _seed;
    if (seed != null) return _sanitize(seed);
    _load();
    return _default;
  }

  Future<void> _load() async {
    int saved;
    try {
      final raw = await _storage.read(key: _key);
      saved = _sanitize(int.tryParse(raw ?? '') ?? _default);
    } catch (_) {
      saved = _default;
    }
    if (!_userChose && saved != state) state = saved;
  }

  void select(int tab) {
    _userChose = true;
    state = tab;
    // Best-effort persistence; failure is non-fatal.
    _storage.write(key: _key, value: '$tab').catchError((_) {});
  }
}

final appTabProvider = NotifierProvider<AppTabNotifier, int>(
  AppTabNotifier.new,
);
