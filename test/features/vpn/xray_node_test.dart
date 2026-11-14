// Pure VLESS parsing + xray config generation (no dart:io).
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mide/features/vpn/xray/xray_node.dart';

void main() {
  group('XrayNode.parse', () {
    test('reads the query parameters of a ws+tls link', () {
      final n = XrayNode.parse(
        'vless://uuid-1@203.0.113.10:443'
        '?type=ws&security=tls&sni=cdn.example.com&path=%2Fws'
        '&host=front.example.com&fp=chrome#DE%20%7C%20node',
      )!;
      expect(n.uuid, 'uuid-1');
      expect(n.host, '203.0.113.10');
      expect(n.port, 443);
      expect(n.network, 'ws');
      expect(n.security, 'tls');
      expect(n.sni, 'cdn.example.com');
      expect(n.path, '/ws');
      expect(n.hostHeader, 'front.example.com');
      expect(n.fingerprint, 'chrome');
      expect(n.name, 'DE');
    });

    test('defaults port to 443 and network to tcp', () {
      final n = XrayNode.parse('vless://u@host.example#n')!;
      expect(n.port, 443);
      expect(n.network, 'tcp');
      expect(n.security, 'none');
      expect(n.path, '/');
    });

    test('treats an empty flow as null', () {
      expect(XrayNode.parse('vless://u@h.example?flow=#x')!.flow, isNull);
      expect(
        XrayNode.parse('vless://u@h.example?flow=xtls-rprx-vision#x')!.flow,
        'xtls-rprx-vision',
      );
    });

    test('rejects non-vless schemes and malformed links', () {
      expect(XrayNode.parse('vmess://abc@host:443'), isNull);
      expect(XrayNode.parse('trojan://abc@host:443'), isNull);
      expect(XrayNode.parse('vless://host-only'), isNull);
      expect(XrayNode.parse('not a link at all'), isNull);
    });
  });

  group('XrayNode.buildConfig', () {
    test('emits local socks+http inbounds and RU-direct routing', () {
      final n = XrayNode.parse(
        'vless://u-i-d@1.2.3.4:443?type=ws&security=tls',
      )!;
      final cfg = jsonDecode(n.toJsonConfig()) as Map<String, dynamic>;

      final ports = (cfg['inbounds'] as List).map((i) => i['port']).toSet();
      expect(ports, containsAll([XrayNode.socksPort, XrayNode.httpPort]));

      final out = (cfg['outbounds'] as List).first as Map<String, dynamic>;
      expect(out['protocol'], 'vless');

      final rules = ((cfg['routing'] as Map)['rules'] as List)
          .cast<Map<String, dynamic>>();
      expect(
        rules.any(
          (r) =>
              r['domain'] is List &&
              (r['domain'] as List).contains('geosite:category-ru'),
        ),
        isTrue,
      );
      expect(
        rules.any(
          (r) => r['ip'] is List && (r['ip'] as List).contains('geoip:private'),
        ),
        isTrue,
      );
    });

    test('reality nodes carry publicKey, shortId and serverName', () {
      final n = XrayNode.parse(
        'vless://u@1.2.3.4:443'
        '?type=tcp&security=reality&sni=www.microsoft.com'
        '&pbk=PUBKEY&sid=18e9ea38&flow=xtls-rprx-vision#DE',
      )!;
      final cfg = jsonDecode(n.toJsonConfig()) as Map<String, dynamic>;
      final out = (cfg['outbounds'] as List).first as Map<String, dynamic>;
      final ss = out['streamSettings'] as Map<String, dynamic>;
      final reality = ss['realitySettings'] as Map<String, dynamic>;
      expect(reality['serverName'], 'www.microsoft.com');
      expect(reality['publicKey'], 'PUBKEY');
      expect(reality['shortId'], '18e9ea38');

      final users =
          ((out['settings'] as Map)['vnext'] as List).first['users'] as List;
      expect((users.first as Map)['flow'], 'xtls-rprx-vision');
    });

    test('network-specific stream settings (grpc / httpupgrade / xhttp)', () {
      Map<String, dynamic> ssOf(String link) {
        final cfg = jsonDecode(
          XrayNode.parse(link)!.toJsonConfig(),
        ) as Map<String, dynamic>;
        final out = (cfg['outbounds'] as List).first as Map<String, dynamic>;
        return out['streamSettings'] as Map<String, dynamic>;
      }

      expect(
        ssOf(
          'vless://u@h:443?type=grpc&security=tls&path=/svc#x',
        )['grpcSettings'],
        {'serviceName': 'svc'},
      );
      expect(
        ssOf(
          'vless://u@h:443?type=httpupgrade&security=tls&path=/up#x',
        )['httpupgradeSettings'],
        {'path': '/up'},
      );
      expect(
        (ssOf(
              'vless://u@h:443?type=xhttp&security=tls&path=/xh#x',
            )['xhttpSettings']
            as Map)['mode'],
        'auto',
      );
    });

    test('tls settings fall back to the host when no sni is given', () {
      final cfg = jsonDecode(
        XrayNode.parse('vless://u@1.2.3.4:443?type=ws&security=tls')!
            .toJsonConfig(),
      ) as Map<String, dynamic>;
      final ss =
          ((cfg['outbounds'] as List).first
                  as Map<String, dynamic>)['streamSettings']
              as Map<String, dynamic>;
      expect((ss['tlsSettings'] as Map)['serverName'], '1.2.3.4');
    });
  });
}
