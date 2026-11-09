// Theme selection state — persisted via secure storage.
//
// The persisted value is resolved synchronously up-front (see
// [ThemeChoiceNotifier.loadPersisted]) and handed to the notifier as a
// [seed]. That means the very first frame already paints the user's saved
// theme instead of flashing the default palette and then "lightening up".
//
// A fresh [select] applies immediately in memory and serializes storage
// writes so rapid theme switches persist in order (the last pick always
// wins — no stale "reset" on the next launch).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The two "bloody" themes the user can pick from (carousel in settings).
enum MideThemeChoice {
  lightBloody('Кровавая светлая', 'Светлая с кровавым акцентом'),
  darkBloody('Кровавая тёмная', 'Тёмная с кровавым акцентом');

  const MideThemeChoice(this.label, this.subtitle);

  final String label;
  final String subtitle;

  bool get isDark => this == MideThemeChoice.darkBloody;
}

class ThemeChoiceNotifier extends Notifier<MideThemeChoice> {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const _key = 'mide_theme_choice';
  static const _default = MideThemeChoice.lightBloody;

  /// Read the persisted theme off the main isolate *before* the first frame.
  ///
  /// [FlutterSecureStorage] requires the widgets binding to be initialized
  /// before it can talk to the platform channel, so callers must run
  /// `WidgetsFlutterBinding.ensureInitialized()` first. Any read failure
  /// falls back to [_default] so launch never blocks on storage.
  static Future<MideThemeChoice> loadPersisted() async {
    try {
      final raw = await _storage.read(key: _key);
      if (raw != null) {
        for (final choice in MideThemeChoice.values) {
          if (choice.name == raw) return choice;
        }
      }
    } catch (_) {
      // Non-fatal: fall back to the default theme on first paint.
    }
    return _default;
  }

  bool _userChose = false;

  /// Authoritative theme resolved before the first frame (see
  /// [loadPersisted]). When null, the notifier starts from the default and
  /// the background loader fills in the saved value.
  final MideThemeChoice? _seed;

  /// Serializes storage writes so rapid theme switches persist in order
  /// (the last pick always wins — no stale "reset" on the next launch).
  Future<void> _writeChain = Future.value();

  ThemeChoiceNotifier({MideThemeChoice? seed})
      : _seed = seed,
        _userChose = seed != null {
    // A non-null seed already reflects the persisted choice, so treat it as
    // "the user chose this value" and skip the background reload.
  }

  @override
  MideThemeChoice build() {
    final seed = _seed;
    if (seed != null) return seed;
    _load();
    return _default;
  }

  Future<void> _load() async {
    final saved = await loadPersisted();
    // Only apply the persisted value if the user hasn't picked in the meantime.
    if (!_userChose && saved != state) state = saved;
  }

  Future<void> select(MideThemeChoice choice) async {
    _userChose = true;
    state = choice;
    _writeChain = _writeChain.then((_) => _storage.write(key: _key, value: choice.name));
    try {
      await _writeChain;
    } catch (_) {
      // Non-fatal: the choice still applies for this session.
    }
  }
}

final themeChoiceProvider =
    NotifierProvider<ThemeChoiceNotifier, MideThemeChoice>(
  ThemeChoiceNotifier.new,
);
