// The VPN credential store is the only thing standing between a subscription
// key and a plaintext file, so its normalisation rules are worth pinning.
// The secure-storage method channel is faked; the store logic is real.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mide/features/vpn/vpn_settings.dart';

const _channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Map<String, String> disk;

  setUp(() {
    disk = {};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          final args = Map<String, dynamic>.from(
            (call.arguments as Map?) ?? const {},
          );
          final key = args['key'] as String?;
          switch (call.method) {
            case 'read':
              return disk[key];
            case 'write':
              disk[key!] = args['value'] as String? ?? '';
              return null;
            case 'delete':
              disk.remove(key);
              return null;
            case 'readAll':
              return disk;
            case 'deleteAll':
              disk.clear();
              return null;
            case 'containsKey':
              return disk.containsKey(key);
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  group('VpnSettings', () {
    test('hasKey ignores whitespace-only keys', () {
      expect(const VpnSettings(apiKey: '', baseUrl: 'x').hasKey, isFalse);
      expect(const VpnSettings(apiKey: '   ', baseUrl: 'x').hasKey, isFalse);
      expect(const VpnSettings(apiKey: 'abc', baseUrl: 'x').hasKey, isTrue);
    });
  });

  group('VpnSettingsStore', () {
    test('a fresh install reports the default endpoint and no key', () async {
      const store = VpnSettingsStore();
      final settings = await store.load();

      expect(settings.apiKey, '');
      expect(settings.baseUrl, VpnSettingsStore.defaultBaseUrl);
      expect(settings.hasKey, isFalse);
    });

    test('round-trips a saved key and endpoint', () async {
      const store = VpnSettingsStore();
      await store.save(
        const VpnSettings(apiKey: 'secret-key', baseUrl: 'https://vpn.test'),
      );

      final loaded = await store.load();
      expect(loaded.apiKey, 'secret-key');
      expect(loaded.baseUrl, 'https://vpn.test');
    });

    test('trims stray whitespace a paste can bring in', () async {
      const store = VpnSettingsStore();
      await store.save(
        const VpnSettings(
          apiKey: '  secret-key\n',
          baseUrl: '  https://vpn.test  ',
        ),
      );

      final loaded = await store.load();
      expect(loaded.apiKey, 'secret-key');
      expect(loaded.baseUrl, 'https://vpn.test');
    });

    test('an emptied endpoint falls back to the default, not to ""', () async {
      const store = VpnSettingsStore();
      await store.save(const VpnSettings(apiKey: 'k', baseUrl: '   '));

      final loaded = await store.load();
      expect(loaded.baseUrl, VpnSettingsStore.defaultBaseUrl);
    });

    test('clear removes the key instead of leaving it on disk', () async {
      const store = VpnSettingsStore();
      await store.save(
        const VpnSettings(apiKey: 'secret-key', baseUrl: 'https://vpn.test'),
      );
      await store.clear();

      final loaded = await store.load();
      expect(loaded.apiKey, isEmpty);
      expect(loaded.hasKey, isFalse);
    });
  });
}
