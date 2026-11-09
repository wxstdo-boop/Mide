// Unit tests for VPN API parsing helpers + UI smoke test.
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mide/features/vpn/free_vpn_sources.dart';
import 'package:mide/features/vpn/vpn_api_client.dart';
import 'package:mide/features/vpn/xray/xray_node.dart';
import 'package:mide/main.dart';

void main() {
  group('WarpSource.buildConf', () {
    test('turns a registration response into a wg-quick config', () {
      final conf = WarpSource.buildConf({
        'interface': {
          'private_key': 'aGF2ZXlhYnllbg==',
          'addresses': {
            'v4': '172.16.0.5/32',
            'v6': '2606:4700:1234::5678/128',
          },
        },
        'peer': {
          'public_key': 'c2VydmVycHVi',
          'endpoint': {
            'v4': 'engage.cloudflareclient.com:2408',
          },
        },
      });
      expect(conf, contains('PrivateKey = aGF2ZXlhYnllbg=='));
      expect(conf, contains('Address = 2606:4700:1234::5678/128, 172.16.0.5/32'));
      expect(conf, contains('PublicKey = c2VydmVycHVi'));
      expect(conf, contains('AllowedIPs = 0.0.0.0/0, ::/0'));
      expect(conf, contains('PresharedKey = AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA='));
    });

    test('rejects responses without keys', () {
      expect(
        WarpSource.buildConf({
          'interface': {'addresses': {}},
        }),
        isEmpty,
      );
    });
  });

  group('ApiVpnServer.fromJson', () {
    test('parses a flat server object', () {
      final s = ApiVpnServer.fromJson({
        'id': 'ams1',
        'name': 'Amsterdam',
        'country': 'Netherlands',
        'countryCode': 'NL',
        'flag': 'NL',
        'ping': 18,
        'load': 0.23,
      });
      expect(s.id, 'ams1');
      expect(s.name, 'Amsterdam');
      expect(s.country, 'Netherlands');
      expect(s.countryCode, 'NL');
      expect(s.flag, 'NL');
      expect(s.pingMs, 18);
      expect(s.loadPercent, closeTo(0.23, 0.001));
    });

    test('handles missing optional fields', () {
      final s = ApiVpnServer.fromJson({'id': 'x', 'name': 'Server'});
      expect(s.id, 'x');
      expect(s.name, 'Server');
      expect(s.pingMs, isNull);
      expect(s.loadPercent, isNull);
    });
  });

  group('ApiConnectResult.fromJson', () {
    test('reads ip and protocol', () {
      final r =
          ApiConnectResult.fromJson({'ip': '1.2.3.4', 'protocol': 'WireGuard'});
      expect(r.ipAddress, '1.2.3.4');
      expect(r.protocol, 'WireGuard');
    });
  });

  group('XrayNode.parse', () {
    test('parses a VLESS ws+tls link', () {
      final n = XrayNode.parse(
          'vless://1b8a5f4c-2f9e-4d7a-9f3b-1c2d3e4f5a6b@104.17.148.22:443'
          '?type=ws&security=tls&sni=cdncache.duckdns.org&path=%2Fv2ray'
          '&host=www.speedtest.net&fp=chrome#NL%20%7C%20node1');
      expect(n, isNotNull);
      expect(n!.uuid, '1b8a5f4c-2f9e-4d7a-9f3b-1c2d3e4f5a6b');
      expect(n.host, '104.17.148.22');
      expect(n.port, 443);
      expect(n.network, 'ws');
      expect(n.security, 'tls');
      expect(n.sni, 'cdncache.duckdns.org');
      expect(n.path, '/v2ray');
      expect(n.hostHeader, 'www.speedtest.net');
      expect(n.name, 'NL');
    });

    test('returns null for non-vless schemes', () {
      expect(XrayNode.parse('vmess://abcd@host:443'), isNull);
      expect(XrayNode.parse('not a link'), isNull);
    });

    test('builds xray JSON with inbounds and RU-direct routing', () {
      final n = XrayNode.parse(
          'vless://u-i-d@h.example:443?type=tls&security=tls&sni=h.example')!;
      final cfg = jsonDecode(n.toJsonConfig()) as Map<String, dynamic>;
      final inbounds = cfg['inbounds'] as List;
      expect(inbounds.map((i) => i['port']),
          containsAll([XrayNode.socksPort, XrayNode.httpPort]));
      final out = (cfg['outbounds'] as List).first as Map<String, dynamic>;
      expect(out['protocol'], 'vless');
      final rules =
          ((cfg['routing'] as Map)['rules'] as List).cast<Map<String, dynamic>>();
      expect(
          rules.any((r) =>
              r['domain'] is List && (r['domain'] as List).contains('geosite:category-ru')),
          isTrue);
      final ss = out['streamSettings'] as Map<String, dynamic>;
      expect(ss['tlsSettings'], isNotNull);
      expect((ss['tlsSettings'] as Map)['serverName'], 'h.example');
    });

    test('reality nodes carry their public key and fingerprint', () {
      final n = XrayNode.parse('vless://u-i-d@1.2.3.4:443'
          '?type=tcp&security=reality&sni=www.microsoft.com'
          '&pbk=SdBpEKuLgLVZVPQFOXTBBnTLFJyLTsndWMJlBRZWBX0'
          '&fp=chrome&sid=18e9ea38&flow=xtls-rprx-vision#DE')!;
      expect(n.security, 'reality');
      expect(n.pbk, 'SdBpEKuLgLVZVPQFOXTBBnTLFJyLTsndWMJlBRZWBX0');
      expect(n.flow, 'xtls-rprx-vision');
      final cfg = jsonDecode(n.toJsonConfig()) as Map<String, dynamic>;
      final out = (cfg['outbounds'] as List).first as Map<String, dynamic>;
      final ss = out['streamSettings'] as Map<String, dynamic>;
      final reality = ss['realitySettings'] as Map<String, dynamic>;
      expect(reality['serverName'], 'www.microsoft.com');
      expect(reality['publicKey'], n.pbk);
      expect(reality['shortId'], '18e9ea38');
      expect(
        (out['settings'] as Map)['vnext']
            .first['users']
            .first['flow'],
        'xtls-rprx-vision',
      );
    });
  });

  testWidgets('home screen renders without API key', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: MideApp()));
    await tester.pump();
    // Let the launch splash play out and lift itself off the tree.
    await tester.pump(const Duration(milliseconds: 2900));
    await tester.pumpAndSettle();

    expect(find.text('Mide'), findsOneWidget);
  });

  testWidgets('bottom pills show all three tabs', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: MideApp()));
    await tester.pump();
    // Clear the launch splash.
    await tester.pump(const Duration(milliseconds: 2900));
    await tester.pumpAndSettle();

    // All three pills are visible.
    expect(find.text('AGI'), findsOneWidget);
    expect(find.text('NPV'), findsOneWidget);
    expect(find.text('MEarn'), findsOneWidget);
  });

  testWidgets('VPN card offers only ON/OFF plus built-in servers',
      (tester) async {
    await tester.pumpWidget(const ProviderScope(child: MideApp()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 2900));
    await tester.pumpAndSettle();

    // A single toggle, no import flow anywhere.
    expect(find.text('Включить VPN'), findsOneWidget);
    expect(find.textContaining('импорт'), findsNothing);
    expect(find.textContaining('Импорт'), findsNothing);

    // The two transports measured working from an RF ISP ship in the box.
    expect(find.text('V2Nodes · WebSocket'), findsOneWidget);
    expect(find.text('V2Nodes · Reality'), findsOneWidget);
    expect(find.text('VPNBook'), findsNothing);
  });

  testWidgets('bottom pills switch between tabs', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: MideApp()));
    await tester.pump();
    // Clear the launch splash.
    await tester.pump(const Duration(milliseconds: 2900));
    await tester.pumpAndSettle();

    // Switching to the AGI tab shows the AI section.
    await tester.tap(find.text('AGI'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('АДУСЯ'), findsOneWidget);
    expect(find.text('M.AI'), findsOneWidget);
    expect(find.text('Ада'), findsOneWidget);

    // Switch to MEarn tab.
    await tester.tap(find.text('MEarn'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Kryptex'), findsOneWidget);

    // Back to NPV tab: header is visible.
    await tester.tap(find.text('NPV'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Mide'), findsOneWidget);
  });
}
