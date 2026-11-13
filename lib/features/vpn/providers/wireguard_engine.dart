// Real cross-platform WireGuard tunnel engine.
// Uses `wireguard_flutter_pro`:
//   - Android  → com.wireguard.android VpnService (no root)
//   - Windows  → Wintun + wireguard-go C-API (must run as admin)
//   - macOS/iOS→ Apple Packet Tunnel extension
//   - Linux    → wg-quick CLI
// On Web the plugin is unsupported and the engine degrades gracefully.
import 'package:flutter/foundation.dart';
import 'package:wireguard_flutter_pro/wireguard_flutter.dart'
    show VpnStage;
import 'package:wireguard_flutter_pro/wireguard_flutter_platform_interface.dart'
    show WireGuardFlutterInterface;
import 'package:wireguard_flutter_pro/wireguard_flutter.dart'
    show WireGuardFlutter;

class WireguardEngine {
  static final WireguardEngine instance = WireguardEngine._();
  WireguardEngine._();

  bool _ready = false;
  bool get ready => _ready;

  WireGuardFlutterInterface? _wg;

  Future<void> init() async {
    if (_ready || kIsWeb) return;
    try {
      _wg = WireGuardFlutter.instance;
      await _wg!.initialize(interfaceName: 'mide_wg');
      _ready = true;
    } catch (_) {
      // Unsupported platform or permission denied — engine stays off.
      _ready = false;
    }
  }

  Future<void> connect({
    required String serverAddress,
    required String wgQuickConfig,
    String providerId = 'com.example.mide',
  }) async {
    await init();
    if (_wg == null) throw StateError('Tunnel engine not available on this platform');
    await _wg!.startVpn(
      serverAddress: serverAddress,
      wgQuickConfig: wgQuickConfig,
      providerBundleIdentifier: providerId,
    );
  }

  Future<void> disconnect() async {
    if (_wg == null) return;
    try {
      await _wg!.stopVpn();
    } catch (_) {}
  }

  Future<VpnStage> getStage() async {
    if (_wg == null) return VpnStage.noConnection;
    try {
      return await _wg!.stage();
    } catch (_) {
      return VpnStage.disconnected;
    }
  }

  /// Live stream of stage changes (connected / connecting / disconnected …).
  Stream<VpnStage> get stageStream => _wg?.vpnStageSnapshot ?? const Stream.empty();

  /// Parses the `Endpoint` value from a wg-quick config string.
  static String? parseEndpoint(String conf) {
    final m = RegExp(
        r'^\s*Endpoint\s*=\s*(\S+)',
        multiLine: true,
        caseSensitive: false,
    ).firstMatch(conf);
    return m?.group(1)?.trim();
  }
}
