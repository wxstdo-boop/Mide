// Built-in free VPN sources — no manual import, no API key.
//
// Cloudflare WARP: registers a throw-away client at Cloudflare's public
// enrollment endpoint (the same flow warp-go / wgcf use), gets a personal
// WireGuard peer back and turns it into a wg-quick .conf. Free, unlimited,
// no captcha; the SNI filtering of some RF ISPs still kills it, which is why
// the Xray path exists.
//
// V2Nodes: publishes VLESS nodes (xray-core family). A WireGuard tunnel
// cannot carry those, so on Windows the app drives an Xray core itself
// (see features/vpn/xray/), on other platforms the entry explains why not.
import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:dio/dio.dart';

class FreeVpnException implements Exception {
  final String message;
  const FreeVpnException(this.message);
  @override
  String toString() => message;
}

/// Comment tag marking who owns a persisted .conf, so we don't
/// re-provision on every toggle.
const String kWarpSourceTag = '# mide-source: cloudflare-warp';

class WarpSource {
  static const _regUrl = 'https://api.cloudflareclient.com/v0a2357/reg';
  static const _endpoint = 'engage.cloudflareclient.com:2408';

  /// WARP always uses an all-zero preshared key.
  static const _zeroPsk = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=';

  /// Generates an X25519 keypair, enrolls it with Cloudflare and returns a
  /// ready wg-quick config string.
  static Future<String> generateConf() async {
    final conf = buildConf(await register());
    if (conf.isEmpty) {
      throw const FreeVpnException(
        'Cloudflare вернул пустой конфиг — попробуй ещё раз',
      );
    }
    return conf;
  }

  static Future<Map<String, dynamic>> register() async {
    final (privB64, pubB64) = await _generateKeypair();
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 12),
        receiveTimeout: const Duration(seconds: 15),
        headers: {
          'Content-Type': 'application/json',
          'User-Agent': 'okhttp/4.12.0',
        },
      ),
    );
    try {
      final res = await dio.post<dynamic>(
        _regUrl,
        data: jsonEncode({
          'key': pubB64,
          'fingerprint': _randomFingerprint(),
          'install_id': '',
          'token_type': 'appV1',
          'license_type': 'free',
        }),
      );
      final data = res.data;
      if (data is Map && data['interface'] is Map) {
        final out = Map<String, dynamic>.from(data);
        final iface = Map<String, dynamic>.from(out['interface'] as Map);
        // Cloudflare normally echoes our keypair back; keep the local
        // private key as the source of truth regardless.
        if ((iface['private_key'] ?? '').toString().isEmpty) {
          iface['private_key'] = privB64;
        }
        out['interface'] = iface;
        return out;
      }
      throw const FreeVpnException(
        'Cloudflare не выдал туннель (ответ без конфига)',
      );
    } on DioException catch (e) {
      throw FreeVpnException(_friendlyDioError(e, 'Cloudflare WARP'));
    } finally {
      dio.close(force: true);
    }
  }

  /// Maps a registration response to a wg-quick .conf. Kept pure for tests.
  static String buildConf(Map<String, dynamic> d) {
    final iface = Map<String, dynamic>.from(d['interface'] as Map);
    final peer = Map<String, dynamic>.from(
      (d['peer'] ?? const <String, dynamic>{}) as Map,
    );
    final addrs = Map<String, dynamic>.from(
      (iface['addresses'] ?? const <String, dynamic>{}) as Map,
    );
    final allowed = Map<String, dynamic>.from(
      (peer['allowed_ips'] ?? const <String, dynamic>{}) as Map,
    );
    final serverPub = (peer['public_key'] ?? d['key'] ?? '').toString();
    final v4 = (addrs['v4'] ?? '').toString();
    final v6 = (addrs['v6'] ?? '').toString();
    final private = (iface['private_key'] ?? '').toString();
    if (private.isEmpty || serverPub.isEmpty) return '';
    final allowedIps = [
      (allowed['v4'] ?? '0.0.0.0/0').toString(),
      (allowed['v6'] ?? '::/0').toString(),
    ].join(', ');
    return [
      '[Interface]',
      'PrivateKey = $private',
      'Address = ${[if (v6.isNotEmpty) v6, if (v4.isNotEmpty) v4].join(', ')}',
      'MTU = 1280',
      '',
      '[Peer]',
      'PublicKey = $serverPub',
      'PresharedKey = $_zeroPsk',
      'Endpoint = $_endpoint',
      'AllowedIPs = $allowedIps',
      'PersistentKeepalive = 25',
      '',
    ].join('\n');
  }

  static Future<(String, String)> _generateKeypair() async {
    final kp = await X25519().newKeyPair();
    final priv = base64Encode(await kp.extractPrivateKeyBytes());
    final pub = base64Encode((await kp.extractPublicKey()).bytes);
    return (priv, pub);
  }

  /// 8 chars, letters+digits only — Cloudflare rejects '-' and '_'.
  static String _randomFingerprint() {
    const chars = 'abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final r = Random.secure();
    return List.generate(8, (_) => chars[r.nextInt(chars.length)]).join();
  }
}

class V2NodesSource {
  static const String notice =
      'V2Nodes отдаёт VLESS-ноды — на Windows они подключаются '
      'встроенным Xray-ядром (эти серверы). На других платформах '
      'WireGuard-туннель их повезти не может.';
}

String _friendlyDioError(DioException e, String who) {
  switch (e.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.receiveTimeout:
    case DioExceptionType.sendTimeout:
      return '$who: превышен таймаут сети';
    case DioExceptionType.connectionError:
      return '$who недоступен из твоей сети '
          '(обычно блокируется DPI) — попробуй WARP';
    default:
      final code = e.response?.statusCode;
      return code == null ? '$who: сеть недоступна' : '$who: HTTP $code';
  }
}
