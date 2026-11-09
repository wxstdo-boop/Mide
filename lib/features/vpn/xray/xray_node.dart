// Pure VLESS-link parsing + xray config generation (no dart:io, web-safe).
import 'dart:convert';

class XrayException implements Exception {
  final String message;
  const XrayException(this.message);
  @override
  String toString() => message;
}

/// One parsed `vless://uuid@host:port?...#name` link.
class XrayNode {
  final String uuid;
  final String host;
  final int port;
  final String network; // tcp|ws|grpc|xhttp|httpupgrade
  final String security; // none|tls|reality
  final String? sni;
  final String path;
  final String? hostHeader;
  final String? flow;
  final String? pbk;
  final String? sid;
  final String? fingerprint;
  final String name;

  const XrayNode({
    required this.uuid,
    required this.host,
    required this.port,
    required this.network,
    required this.security,
    required this.path,
    required this.name,
    this.sni,
    this.hostHeader,
    this.flow,
    this.pbk,
    this.sid,
    this.fingerprint,
  });

  static const socksPort = 10808;
  static const httpPort = 12880;

  /// Returns null for anything we don't speak (vmess:// etc.) or malformed.
  static XrayNode? parse(String link) {
    if (!link.startsWith('vless://')) return null;
    Uri u;
    try {
      u = Uri.parse(link);
    } catch (_) {
      return null;
    }
    if (u.host.isEmpty || u.userInfo.isEmpty) return null;
    final q = u.queryParameters;
    return XrayNode(
      uuid: u.userInfo.split('@').first,
      host: u.host,
      port: u.hasPort ? u.port : 443,
      network: q['type'] ?? 'tcp',
      security: q['security'] ?? 'none',
      sni: q['sni'],
      path: q['path'] ?? '/',
      hostHeader: q['host'],
      flow: (q['flow']?.isEmpty ?? true) ? null : q['flow'],
      pbk: q['pbk'],
      sid: q['sid'],
      fingerprint: q['fp'],
      name: Uri.decodeComponent(u.fragment).split('|').first.trim(),
    );
  }

  /// Full xray config: node outbound + local SOCKS/HTTP inbounds +
  /// Russia-direct routing.
  Map<String, dynamic> buildConfig() => {
        'inbounds': [
          {
            'tag': 'socks',
            'port': socksPort,
            'listen': '127.0.0.1',
            'protocol': 'socks',
            'settings': {'auth': 'noauth'},
          },
          {
            'tag': 'http',
            'port': httpPort,
            'listen': '127.0.0.1',
            'protocol': 'http',
            'settings': {'timeout': 0},
          },
        ],
        'outbounds': [
          {
            'protocol': 'vless',
            'settings': {
              'vnext': [
                {
                  'address': host,
                  'port': port,
                  'users': [
                    {
                      'id': uuid,
                      'encryption': 'none',
                      if (flow != null) 'flow': flow,
                    },
                  ],
                },
              ],
            },
            'streamSettings': streamSettings(),
          },
          {'protocol': 'freedom', 'tag': 'direct'},
          {'protocol': 'blackhole', 'tag': 'block'},
        ],
        'routing': {
          'domainStrategy': 'AsIs',
          'rules': [
            {'type': 'field', 'outboundTag': 'direct', 'ip': ['geoip:private']},
            {
              'type': 'field',
              'outboundTag': 'direct',
              'domain': ['geosite:category-ru'],
            },
          ],
        },
        'log': {'loglevel': 'warning'},
      };

  String toJsonConfig() => jsonEncode(buildConfig());

  Map<String, dynamic> streamSettings() {
    final ss = <String, dynamic>{'network': network, 'security': security};
    if (security == 'tls') {
      ss['tlsSettings'] = {
        'serverName': sni ?? host,
        'alpn': ['http/1.1'],
      };
    } else if (security == 'reality') {
      ss['realitySettings'] = {
        'serverName': sni ?? host,
        'fingerprint': fingerprint ?? 'chrome',
        'publicKey': pbk ?? '',
        'shortId': sid ?? '',
      };
      ss['security'] = 'reality';
    }
    switch (network) {
      case 'ws':
        ss['wsSettings'] = {
          'path': path,
          if (hostHeader != null && hostHeader!.isNotEmpty)
            'headers': {'Host': hostHeader},
        };
      case 'httpupgrade':
        ss['httpupgradeSettings'] = {
          'path': path,
          if (hostHeader != null && hostHeader!.isNotEmpty) 'host': hostHeader,
        };
      case 'xhttp':
        ss['xhttpSettings'] = {
          'path': path,
          if (hostHeader != null && hostHeader!.isNotEmpty) 'host': hostHeader,
          'mode': 'auto',
        };
      case 'grpc':
        ss['grpcSettings'] = {'serviceName': path.replaceFirst('/', '')};
    }
    return ss;
  }
}
