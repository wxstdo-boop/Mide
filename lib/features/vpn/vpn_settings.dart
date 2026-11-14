// VPN settings — API key + base URL, stored securely.
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class VpnSettings {
  final String apiKey;
  final String baseUrl;

  const VpnSettings({required this.apiKey, required this.baseUrl});

  bool get hasKey => apiKey.trim().isNotEmpty;
}

class VpnSettingsStore {
  const VpnSettingsStore();

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const _keyApiKey = 'vpn_api_key';
  static const _keyBaseUrl = 'vpn_base_url';
  static const _defaultBaseUrl = 'https://api.yourprovider.com';

  static String get defaultBaseUrl => _defaultBaseUrl;

  Future<VpnSettings> load() async {
    return _loadInternal();
  }

  static Future<VpnSettings> _loadInternal() async {
    final key = await _storage.read(key: _keyApiKey) ?? '';
    final base = await _storage.read(key: _keyBaseUrl) ?? _defaultBaseUrl;
    return VpnSettings(
      apiKey: key,
      baseUrl: base.trim().isEmpty ? _defaultBaseUrl : base.trim(),
    );
  }

  Future<void> save(VpnSettings settings) async {
    await _storage.write(key: _keyApiKey, value: settings.apiKey.trim());
    await _storage.write(
      key: _keyBaseUrl,
      value: settings.baseUrl.trim().isEmpty
          ? _defaultBaseUrl
          : settings.baseUrl.trim(),
    );
  }

  Future<void> clear() async {
    await _storage.delete(key: _keyApiKey);
    await _storage.delete(key: _keyBaseUrl);
  }
}
