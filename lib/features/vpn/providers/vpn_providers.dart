// VPN providers — real cross-platform WireGuard tunnel via wireguard_flutter_pro.
// The ON/OFF toggle drives the native tunnel (Android VpnService / Windows Wintun).
// Free configs are provisioned out of the box (Cloudflare WARP enrollment).
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:wireguard_flutter_pro/wireguard_flutter_pro.dart' as wg;

import '../free_vpn_sources.dart';
import '../vpn_api_client.dart';
import '../vpn_settings.dart';
import '../xray/xray_manager.dart';
import 'wireguard_engine.dart';

/// A VPN server shown in the UI.
class VpnServer {
  final String id;
  final String name;
  final String? country;
  final String? countryCode;
  final String flag;
  final int pingMs;
  final double loadPercent;

  const VpnServer({
    required this.id,
    required this.name,
    this.country,
    this.countryCode,
    this.flag = '\u{1F310}',
    this.pingMs = 0,
    this.loadPercent = 0,
  });

  factory VpnServer.fromApi(ApiVpnServer s) => VpnServer(
    id: s.id,
    name: s.name,
    country: s.country,
    countryCode: s.countryCode,
    flag: s.flag ?? '\u{1F310}',
    pingMs: s.pingMs ?? 0,
    loadPercent: s.loadPercent ?? 0,
  );

  String get label => name;
  String get flagEmoji => flag;
  int get ping => pingMs;
  double get load => loadPercent;
  bool get isRecommended => true;
  bool get isProOnly => false;
}

/// Built-in free servers, shipped out of the box. Only paths that were
/// actually measured working from an RF ISP: the two Xray transports on
/// Windows. Where no core can run (Android, Web) WARP stays, since it is the
/// only tunnel left there.
List<VpnServer> _builtInServers() {
  const xray = [
    VpnServer(
      id: 'v2nodes',
      name: 'V2Nodes · WebSocket',
      country: 'VLESS WS+TLS · Windows',
      countryCode: 'V2',
    ),
    VpnServer(
      id: 'reality',
      name: 'V2Nodes · Reality',
      country: 'VLESS Reality · стойче к DPI',
      countryCode: 'VR',
    ),
  ];
  if (XrayManager.isSupported) return xray;
  return [
    ...xray,
    const VpnServer(
      id: 'warp',
      name: 'Cloudflare WARP',
      country: 'WireGuard · без Xray-ядра',
      countryCode: 'CF',
    ),
  ];
}

enum VpnPhase {
  disconnected,
  connecting,
  connected,
  disconnecting,
  failed,
  denied,
}

class VpnConnectionState {
  final VpnPhase phase;
  final String? serverId;
  final DateTime? connectedAt;
  final String? ipAddress;
  final String protocol;
  final String? error;

  const VpnConnectionState({
    this.phase = VpnPhase.disconnected,
    this.serverId,
    this.connectedAt,
    this.ipAddress,
    this.protocol = 'WireGuard',
    this.error,
  });

  bool get isConnected => phase == VpnPhase.connected;
  bool get isConnecting =>
      phase == VpnPhase.connecting || phase == VpnPhase.disconnecting;

  VpnConnectionState copyWith({
    VpnPhase? phase,
    String? serverId,
    DateTime? connectedAt,
    String? ipAddress,
    String? protocol,
    String? error,
    bool clearError = false,
  }) => VpnConnectionState(
    phase: phase ?? this.phase,
    serverId: serverId ?? this.serverId,
    connectedAt: connectedAt ?? this.connectedAt,
    ipAddress: ipAddress ?? this.ipAddress,
    protocol: protocol ?? this.protocol,
    error: clearError ? null : (error ?? this.error),
  );
}

/// Persisted WireGuard .conf content (import flow).
final wgConfigProvider = NotifierProvider<WgConfigNotifier, String>(
  WgConfigNotifier.new,
);

class WgConfigNotifier extends Notifier<String> {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    wOptions: WindowsOptions(),
    lOptions: LinuxOptions(),
  );
  static const _key = 'mide_wg_config';

  @override
  String build() {
    _load();
    return '';
  }

  Future<void> _load() async {
    try {
      final v = await _storage.read(key: _key);
      if (v != null && v.isNotEmpty) state = v;
    } catch (_) {}
  }

  Future<void> set(String conf) async {
    state = conf;
    try {
      if (conf.trim().isEmpty) {
        await _storage.delete(key: _key);
      } else {
        await _storage.write(key: _key, value: conf);
      }
    } catch (_) {}
  }
}

// Legacy provider API (kept for optional manual provider connect).
final vpnSettingsStoreProvider = Provider<VpnSettingsStore>((ref) {
  return const VpnSettingsStore();
});

final vpnSettingsProvider = FutureProvider<VpnSettings>((ref) async {
  return ref.watch(vpnSettingsStoreProvider).load();
});

// Server presets.
final vpnServersProvider = Provider<List<VpnServer>>(
  (ref) => _builtInServers(),
);

final selectedServerIdProvider = StateProvider<String?>((ref) => 'v2nodes');

// Connection (drives the real tunnel).
final vpnConnectionStateProvider =
    StateNotifierProvider<VpnConnectionNotifier, VpnConnectionState>(
      (ref) => VpnConnectionNotifier(ref),
    );

class VpnConnectionNotifier extends StateNotifier<VpnConnectionState> {
  final Ref _ref;
  StreamSubscription<wg.VpnStage>? _sub;

  VpnConnectionNotifier(this._ref) : super(const VpnConnectionState()) {
    _ref.onDispose(() => _sub?.cancel());
  }

  bool get hasConfig => _ref.read(wgConfigProvider).trim().isNotEmpty;
  bool _xrayActive = false;

  /// Fetches (or reuses) the .conf that backs the WireGuard path. WARP
  /// enrolls a fresh keypair once; the config is then kept in secure storage.
  Future<String> _ensureConfig() async {
    final saved = _ref.read(wgConfigProvider).trim();
    if (saved.contains(kWarpSourceTag)) return saved;
    final conf = '$kWarpSourceTag\n${await WarpSource.generateConf()}';
    await _ref.read(wgConfigProvider.notifier).set(conf);
    return conf;
  }

  Future<void> connect(String serverId) async {
    if (state.isConnecting) return;
    state = state.copyWith(
      phase: VpnPhase.connecting,
      serverId: serverId,
      clearError: true,
    );
    // The Xray transports: free VLESS nodes through the bundled core (Windows).
    const xrayFlavors = {'v2nodes': false, 'reality': true};
    if (xrayFlavors.containsKey(serverId)) {
      final reality = xrayFlavors[serverId]!;
      if (!XrayManager.isSupported) {
        state = state.copyWith(
          phase: VpnPhase.failed,
          error:
              '${V2NodesSource.notice} '
              'На Windows V2Nodes работает через встроенный Xray.',
        );
        return;
      }
      try {
        await XrayManager.instance.start(reality: reality);
        _xrayActive = true;
        state = VpnConnectionState(
          phase: VpnPhase.connected,
          serverId: serverId,
          connectedAt: DateTime.now(),
          ipAddress: XrayManager.instance.exitIp,
          protocol: reality
              ? 'VLESS Reality · Xray · системный прокси'
              : 'VLESS WebSocket · Xray · системный прокси',
        );
      } catch (e) {
        state = state.copyWith(phase: VpnPhase.failed, error: e.toString());
      }
      return;
    }
    final String conf;
    try {
      conf = await _ensureConfig();
    } catch (e) {
      state = state.copyWith(phase: VpnPhase.failed, error: e.toString());
      return;
    }
    final endpoint =
        WireguardEngine.parseEndpoint(conf) ??
        'engage.cloudflareclient.com:2408';
    await _sub?.cancel();
    _sub = WireguardEngine.instance.stageStream.listen((stage) {
      switch (stage) {
        case wg.VpnStage.connected:
          state = state.copyWith(
            phase: VpnPhase.connected,
            connectedAt: DateTime.now(),
            clearError: true,
          );
        case wg.VpnStage.denied:
          state = state.copyWith(
            phase: VpnPhase.denied,
            error: '\u0421\u0438\u0441\u0442\u0435\u043C\u0430 \u043E\u0442\u043A\u043B\u043E\u043D\u0438\u043B\u0430 VPN-\u0440\u0430\u0437\u0440\u0435\u0448\u0435\u043D\u0438\u0435',
          );
        case wg.VpnStage.disconnected:
        case wg.VpnStage.noConnection:
        case wg.VpnStage.exiting:
          if (!state.isConnected) {
            state = state.copyWith(
              phase: VpnPhase.disconnected,
              clearError: true,
            );
          }
        default:
          break;
      }
    });
    try {
      await WireguardEngine.instance.connect(
        serverAddress: endpoint,
        wgQuickConfig: conf,
      );
    } catch (e) {
      state = state.copyWith(phase: VpnPhase.failed, error: e.toString());
    }
  }

  Future<void> disconnect() async {
    if (state.phase == VpnPhase.disconnected && !_xrayActive) return;
    state = state.copyWith(phase: VpnPhase.disconnecting, clearError: true);
    if (_xrayActive) {
      _xrayActive = false;
      try {
        await XrayManager.instance.stop();
      } catch (_) {}
    } else {
      try {
        await WireguardEngine.instance.disconnect();
      } catch (_) {}
    }
    state = const VpnConnectionState();
  }

  void toggle(String serverId) {
    if (state.isConnected) {
      if (state.serverId == serverId) {
        disconnect();
      } else {
        connect(serverId);
      }
      return;
    }
    connect(serverId);
  }

  /// Pull-to-refresh: re-query the native engine's stage so the card
  /// reflects the real tunnel state even after a manual disconnect.
  Future<void> stageRefresh() async {
    if (_xrayActive) {
      if (!XrayManager.instance.isRunning) {
        _xrayActive = false;
        state = const VpnConnectionState();
      }
      return;
    }
    try {
      final stage = await WireguardEngine.instance.getStage();
      if (stage == wg.VpnStage.connected && !state.isConnected) {
        state = state.copyWith(
          phase: VpnPhase.connected,
          serverId: state.serverId ?? 'warp',
          clearError: true,
        );
      } else if (stage == wg.VpnStage.disconnected && state.isConnected) {
        state = const VpnConnectionState();
      }
    } catch (_) {
      // Engine unavailable (web) — nothing to refresh.
    }
  }
}

/// Live metrics placeholder.
class VpnMetrics {
  final double downloadMbps;
  final double uploadMbps;
  final int latencyMs;
  final int bytesReceived;
  final int bytesSent;
  final DateTime lastUpdated;

  const VpnMetrics({
    this.downloadMbps = 0,
    this.uploadMbps = 0,
    this.latencyMs = 0,
    this.bytesReceived = 0,
    this.bytesSent = 0,
    required this.lastUpdated,
  });
}

final vpnMetricsProvider = StreamProvider<VpnMetrics>((ref) async* {
  ref.watch(vpnConnectionStateProvider);
  while (true) {
    final st = ref.read(vpnConnectionStateProvider);
    if (!st.isConnected) {
      yield VpnMetrics(lastUpdated: DateTime.now());
      await Future.delayed(const Duration(milliseconds: 500));
      continue;
    }
    await Future.delayed(const Duration(seconds: 1));
    final now = DateTime.now();
    yield VpnMetrics(
      downloadMbps: 12.5 + (now.millisecond % 40),
      uploadMbps: 4.0 + (now.millisecond % 15),
      latencyMs: 15 + (now.millisecond % 20),
      bytesReceived: 1024 * 1024 * (now.millisecond % 500),
      bytesSent: 1024 * 512 * (now.millisecond % 200),
      lastUpdated: now,
    );
  }
});
