// Pure helpers of the built-in free-VPN sources and the WireGuard engine.
import 'package:flutter_test/flutter_test.dart';
import 'package:mide/features/vpn/free_vpn_sources.dart';
import 'package:mide/features/vpn/providers/wireguard_engine.dart';

void main() {
  group('WarpSource.buildConf', () {
    test('maps a full registration response to a wg-quick config', () {
      final conf = WarpSource.buildConf({
        'interface': {
          'private_key': 'PRIV=',
          'addresses': {'v4': '172.16.0.2/32', 'v6': '2606:4700::1/128'},
        },
        'peer': {
          'public_key': 'SRVPUB=',
          'endpoint': {'v4': 'engage.cloudflareclient.com:2408'},
          'allowed_ips': {'v4': '0.0.0.0/0', 'v6': '::/0'},
        },
      });
      expect(conf, contains('[Interface]'));
      expect(conf, contains('PrivateKey = PRIV='));
      expect(conf, contains('[Peer]'));
      expect(conf, contains('PublicKey = SRVPUB='));
      expect(conf, contains('Endpoint = engage.cloudflareclient.com:2408'));
      expect(conf, contains('AllowedIPs = 0.0.0.0/0, ::/0'));
      expect(conf, contains('MTU = 1280'));
      expect(conf, contains('PersistentKeepalive = 25'));
    });

    test('falls back to the top-level key when peer has no public_key', () {
      final conf = WarpSource.buildConf({
        'key': 'TOPLEVEL=',
        'interface': {
          'private_key': 'PRIV=',
          'addresses': {'v4': '10.0.0.1/32'},
        },
      });
      expect(conf, contains('PublicKey = TOPLEVEL='));
    });

    test('orders Address as v6 then v4 and defaults AllowedIPs', () {
      final conf = WarpSource.buildConf({
        'interface': {
          'private_key': 'PRIV=',
          'addresses': {'v4': '172.16.0.2/32', 'v6': '2606:4700::1/128'},
        },
        'peer': {'public_key': 'SRVPUB='},
      });
      expect(conf, contains('Address = 2606:4700::1/128, 172.16.0.2/32'));
      expect(conf, contains('AllowedIPs = 0.0.0.0/0, ::/0'));
    });

    test('returns an empty string without a private key or server key', () {
      expect(
          WarpSource.buildConf({
            'interface': {'addresses': {}}
          }),
          isEmpty);
      expect(
        WarpSource.buildConf({
          'interface': {
            'private_key': 'PRIV=',
            'addresses': {'v4': '10.0.0.1/32'},
          },
          'peer': <String, dynamic>{},
        }),
        isEmpty,
      );
    });
  });

  group('WireguardEngine.parseEndpoint', () {
    test('reads the Endpoint value regardless of case and spacing', () {
      const conf =
          '[Peer]\npublicKey = x\n  endpoint = vpn.example.com:51820\n';
      expect(WireguardEngine.parseEndpoint(conf), 'vpn.example.com:51820');
    });

    test('returns null when there is no Endpoint line', () {
      expect(WireguardEngine.parseEndpoint('[Interface]\nPrivateKey = x\n'),
          isNull);
    });
  });
}
