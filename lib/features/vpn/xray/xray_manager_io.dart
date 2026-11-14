// Xray-core sidecar for Windows — the only free path that survives DPI in RF.
// Flow: fetch free VLESS nodes (GitHub mirror of v2nodes-style lists, which
// is reachable even when VPN sites are not) → download Xray-windows-64.zip
// once → run xray.exe with local SOCKS+HTTP inbounds → verify the exit IP
// through the core → point the Windows system proxy (WinINET) at it.
// On OFF: kill the core, restore the direct connection. .ru traffic stays
// direct (geosite:category-ru).
//
// Not a TUN VPN: browsers and WinINET-aware apps route through the core —
// the circumvention surface we control without admin rights.
import 'dart:async';
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';

import 'xray_node.dart';

export 'xray_node.dart';

/// Free VLESS lists — GitHub raw/jsDelivr are reachable from RF networks.
class XrayNodeSource {
  static const _feeds = [
    'https://raw.githubusercontent.com/0xRadikal/Free-v2ray-Configs/main/protocols/vless.txt',
    'https://cdn.jsdelivr.net/gh/0xRadikal/Free-v2ray-Configs@main/protocols/vless.txt',
  ];

  static Future<List<XrayNode>> fetch({
    int limit = 250,
    bool reality = false,
  }) async {
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 12),
        receiveTimeout: const Duration(seconds: 30),
      ),
    );
    Object? lastError;
    try {
      for (final url in _feeds) {
        try {
          final res = await dio.get<String>(
            url,
            options: Options(responseType: ResponseType.plain),
          );
          var nodes = (res.data ?? '')
              .split(RegExp(r'\r?\n'))
              .map(XrayNode.parse)
              .whereType<XrayNode>()
              .toList();
          if (reality) {
            // Reality needs a public key to seal against; ~30% of the feed
            // carries it, and those nodes survive the DPI that kills the
            // Cloudflare-fronted ones.
            nodes = nodes
                .where(
                  (n) =>
                      n.security == 'reality' && (n.pbk?.isNotEmpty ?? false),
                )
                .toList();
          }
          if (nodes.isNotEmpty) {
            // Free nodes die fast; the ones that actually answer are almost
            // always WebSocket+TLS behind Cloudflare on :443 (also the most
            // DPI-tolerant shape), so they go first.
            int rank(XrayNode n) {
              final cf = _cloudflareFronted(n.host);
              if (n.network == 'ws' && n.security == 'tls' && n.port == 443) {
                return cf ? 0 : 2;
              }
              if (n.security == 'reality') return 3;
              if (n.security == 'tls') return 4;
              return 5;
            }

            nodes.sort((a, b) => rank(a).compareTo(rank(b)));
            final head = nodes.take(60).toList()..shuffle(Random.secure());
            return [...head, ...nodes.skip(60)].take(limit).toList();
          }
        } catch (e) {
          lastError = e;
        }
      }
    } finally {
      dio.close(force: true);
    }
    throw XrayException(
      'Не удалось получить список V2Nodes-узлов: ${lastError ?? 'нет сети'}',
    );
  }

  static Future<bool> tcpAlive(XrayNode n, {int timeoutMs = 2500}) async {
    try {
      final s = await Socket.connect(
        n.host,
        n.port,
        timeout: Duration(milliseconds: timeoutMs),
      );
      s.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Cheap reachability screen: do the WebSocket upgrade the node would need
  /// anyway, without paying for an xray spawn. Free lists are heavily
  /// oversubscribed and answer `429`, so this is what actually separates a
  /// usable node from a dead one.
  ///
  /// The node IP is dialed directly and SNI is applied on the upgrade, which
  /// is what the tunnel does too — and it skips a DNS lookup, which this ISP
  /// is known to poison and stall.
  static Future<bool> handshakeAlive(XrayNode n, {int timeoutMs = 5000}) async {
    late Socket raw;
    SecureSocket? s;
    try {
      raw = await Socket.connect(
        n.host,
        n.port,
        timeout: Duration(milliseconds: timeoutMs),
      );
      s = await SecureSocket.secure(
        raw,
        host: n.sni ?? n.host,
        onBadCertificate: (_) => true,
      );
      s.add(
        utf8.encode(
          'GET ${n.path.isEmpty ? '/' : n.path} HTTP/1.1\r\n'
          'Host: ${n.hostHeader ?? n.sni ?? n.host}\r\n'
          'Upgrade: websocket\r\nConnection: Upgrade\r\n'
          'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n'
          'Sec-WebSocket-Version: 13\r\n\r\n',
        ),
      );
      final first = await s
          .take(1)
          .first
          .timeout(Duration(milliseconds: timeoutMs));
      final head = utf8.decode(first, allowMalformed: true);
      final status = RegExp(r'^HTTP/1\.[01] (\d{3})')
          .firstMatch(head)
          ?.group(1);
      // 101 = the tunnel is real; anything else (429 = rate limited edge) is
      // not worth an xray spawn.
      return status == '101';
    } catch (_) {
      return false;
    } finally {
      try {
        s?.destroy();
      } catch (_) {}
    }
  }

  /// Screens [nodes] in parallel batches and returns the ones that completed
  /// a real handshake, best first.
  static Future<List<XrayNode>> screen(
    List<XrayNode> nodes, {
    int want = 4,
    int maxScan = 72,
  }) async {
    final out = <XrayNode>[];
    for (var i = 0; i < nodes.length && out.length < want && i < maxScan;) {
      final batch = nodes.sublist(i, (i + 24).clamp(0, nodes.length));
      i += batch.length;
      final results = await Future.wait(
        batch.map((n) async {
          try {
            final ok = n.network == 'ws'
                ? await handshakeAlive(n)
                : await tcpAlive(n, timeoutMs: 2500);
            return ok ? n : null;
          } catch (_) {
            return null;
          }
        }),
      );
      out.addAll(results.whereType<XrayNode>());
    }
    return out;
  }
}

/// Cloudflare's announced IPv4 ranges — a node behind them is reached over
/// shared infrastructure, which both survives DPI and stays up.
bool _cloudflareFronted(String host) {
  final parts = host.split('.');
  if (parts.length != 4) return false;
  final a = int.tryParse(parts[0]);
  final b = int.tryParse(parts[1]);
  if (a == null || b == null) return false;
  if (a == 104 && b >= 16 && b <= 27) return true;
  if (a == 172 && b >= 64 && b <= 71) return true;
  if (a == 162 && b == 159) return true;
  if (a == 188 && b == 114) return true;
  if (a == 198 && b == 41) return true;
  if (a == 173 && b == 245) return true;
  if (a == 141 && b == 101) return true;
  if (a == 108 && b == 162) return true;
  if (a == 190 && b == 93) return true;
  return false;
}

/// Owns the xray.exe process + the system proxy switch.
class XrayManager {
  XrayManager._();
  static final XrayManager instance = XrayManager._();

  static const _releaseUrl =
      'https://github.com/XTLS/Xray-core/releases/download/v26.3.27/Xray-windows-64.zip';

  static bool get isSupported => Platform.isWindows;

  Process? _proc;
  String? _exitIp;
  String? _activeNodeName;
  bool _proxyApplied = false;

  bool get isRunning => _proc != null;
  String? get exitIp => _exitIp;
  String? get activeNodeName => _activeNodeName;

  Directory get _dir {
    final appData = Platform.environment['APPDATA'] ?? '.';
    return Directory('$appData\\mide\\xray');
  }

  File get _exe => File('${_dir.path}\\xray.exe');

  /// Downloads + extracts the core once (~20 MB), cached forever.
  Future<void> ensureCore() async {
    if (_exe.existsSync()) return;
    await _dir.create(recursive: true);
    final zip = File('${_dir.path}\\xray.zip');
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(minutes: 5),
      ),
    );
    try {
      await dio.download(_releaseUrl, zip.path);
    } catch (e) {
      throw XrayException('Не удалось скачать ядро Xray: $e');
    } finally {
      dio.close(force: true);
    }
    final r = await Process.run('C:\\Windows\\System32\\tar.exe', [
      '-xf',
      zip.path,
      '-C',
      _dir.path,
    ]);
    if (r.exitCode != 0 || !_exe.existsSync()) {
      throw const XrayException('Не удалось распаковать ядро Xray');
    }
    try {
      await zip.delete();
    } catch (_) {}
  }

  /// Kills an xray core left behind by a previous crash: it would hold our
  /// inbound ports and every later spawn then dies on `bind: address busy`.
  /// Scoped to the binary in our own folder so a core the user runs from
  /// elsewhere (v2rayN and friends) is never touched.
  Future<void> _reapStaleCore() async {
    try {
      final ps =
          'Get-CimInstance Win32_Process -Filter "Name=\'xray.exe\'" | '
          "Where-Object { \$_.ExecutablePath -eq '${_exe.path}' } | "
          'ForEach-Object { Stop-Process -Id \$_.ProcessId -Force }';
      final r = await Process.run('powershell.exe', [
        '-NoProfile',
        '-Command',
        ps,
      ]);
      if (r.exitCode == 0) {
        await Future.delayed(const Duration(milliseconds: 500));
      }
    } catch (_) {}
  }

  /// Starts the core on the first node that actually yields a working exit
  /// IP (max [maxTries] candidates). [reality] switches the source to the
  /// VLESS Reality subset, which is the shape that survives SNI filtering.
  /// Throws [XrayException] if none worked.
  Future<void> start({int maxTries = 6, bool reality = false}) async {
    if (_proc != null) return;
    if (!Platform.isWindows) {
      throw const XrayException(
        'Xray-движок встроен для Windows; на телефоне — WARP',
      );
    }
    await ensureCore();
    await _reapStaleCore();
    final nodes = await XrayNodeSource.fetch(reality: reality);
    // Parallel handshake screen first: one xray spawn costs seconds, and most
    // free nodes are rate-limited, so cheap rejection matters.
    final live = await XrayNodeSource.screen(
      nodes,
      want: maxTries,
      maxScan: reality ? 120 : 72,
    );
    if (live.isEmpty) {
      throw const XrayException(
        'Бесплатные узлы V2Nodes сейчас перегружены или мертвы — '
        'список обновляется каждые 15 минут, попробуй ещё раз',
      );
    }
    String? lastReason;
    for (final n in live.take(maxTries)) {
      if (await _spawnAndCheck(n)) {
        await _applySystemProxy();
        return;
      }
      lastReason = _lastSpawnError;
      await _kill();
    }
    throw XrayException(
      'Ни один из ${live.length} живых узлов не дал связь'
      '${lastReason == null ? '' : ': $lastReason'} — '
      'попробуй ещё раз через 15 минут',
    );
  }

  String? _lastSpawnError;

  Future<bool> _spawnAndCheck(XrayNode n) async {
    final cfgFile = File('${_dir.path}\\cfg.json');
    await cfgFile.writeAsString(n.toJsonConfig());
    _lastSpawnError = null;
    final logs = StringBuffer();
    final proc = await Process.start(_exe.path, [
      'run',
      '-c',
      cfgFile.path,
    ], workingDirectory: _dir.path);
    _proc = proc;
    var exited = false;
    proc.exitCode.then((c) {
      exited = true;
      _lastSpawnError = 'ядро завершилось с кодом $c';
    });
    proc.stdout
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen((s) => logs.write(s));
    proc.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen((s) => logs.write(s));
    await Future.delayed(const Duration(milliseconds: 1600));
    if (exited) return false;
    final ip = await _probeExitIp();
    if (ip != null) {
      _exitIp = ip;
      _activeNodeName = n.name;
      return true;
    }
    _lastSpawnError = _reasonFromLog(logs.toString());
    return false;
  }

  /// Turns xray's own log into the one-line reason shown to the user: 429 from
  /// the edge means the free node is oversubscribed, a timeout means DPI or a
  /// dead host, a bind error means a port conflict.
  String? _reasonFromLog(String logs) {
    if (logs.contains('bind:')) return 'порт уже занят другим ядром';
    if (logs.contains('429')) return 'узел перегружен (429)';
    if (logs.contains('bad handshake')) return 'узел отклонил handshake';
    if (logs.contains('i/o timeout') || logs.contains('timed out')) {
      return 'узел не отвечает (DPI или мёртв)';
    }
    return null;
  }

  /// HTTP GET through the local http inbound; returns the exit IP.
  ///
  /// Timeouts are deliberately short: this runs once per candidate node, so a
  /// patient probe would turn a minute-long connect into several.
  Future<String?> _probeExitIp() async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 3);
    client.findProxy = (_) => 'PROXY 127.0.0.1:${XrayNode.httpPort}';
    try {
      final req = await client.getUrl(Uri.parse('https://api.ipify.org/'));
      final res = await req.close().timeout(const Duration(seconds: 5));
      if (res.statusCode != 200) return null;
      final body = await res
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 4));
      final ip = body.trim();
      return RegExp(r'^\d+\.\d+\.\d+\.\d+$').hasMatch(ip) ? ip : null;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  static const _ikey =
      r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings';

  /// WinINET values as they were before we touched them.
  String? _prevProxyEnable;
  String? _prevProxyServer;

  Future<String?> _readValue(String name) async {
    final r = await Process.run('reg.exe', ['query', _ikey, '/v', name]);
    if (r.exitCode != 0) return null;
    final m = RegExp('$name\\s+REG_\\w+\\s+(.+)')
        .firstMatch((r.stdout as String).replaceAll('\r', ''));
    return m?.group(1)?.trim();
  }

  Future<void> _writeValue(String name, String type, String data) =>
      Process.run('reg.exe', [
        'add',
        _ikey,
        '/v',
        name,
        '/t',
        type,
        '/d',
        data,
        '/f',
      ]);

  Future<void> _applySystemProxy() async {
    if (!_proxyApplied) {
      _prevProxyEnable = await _readValue('ProxyEnable');
      _prevProxyServer = await _readValue('ProxyServer');
    }
    const value =
        'http=127.0.0.1:${XrayNode.httpPort};https=127.0.0.1:${XrayNode.httpPort};socks=127.0.0.1:${XrayNode.socksPort}';
    await _writeValue('ProxyEnable', 'REG_DWORD', '1');
    await _writeValue('ProxyServer', 'REG_SZ', value);
    _notifyWinInet();
    _proxyApplied = true;
  }

  Future<void> _clearSystemProxy() async {
    if (!_proxyApplied) return;
    await _writeValue('ProxyEnable', 'REG_DWORD', _prevProxyEnable ?? '0');
    if (_prevProxyServer != null) {
      await _writeValue('ProxyServer', 'REG_SZ', _prevProxyServer!);
    }
    _prevProxyEnable = null;
    _prevProxyServer = null;
    _notifyWinInet();
    _proxyApplied = false;
  }

  /// Broadcasts the WinINET settings change so browsers pick it up live.
  void _notifyWinInet() {
    try {
      final lib = ffi.DynamicLibrary.open('wininet.dll');
      final setOption = lib
          .lookupFunction<
            ffi.Int32 Function(
              ffi.IntPtr,
              ffi.Uint32,
              ffi.Pointer<ffi.Void>,
              ffi.Uint32,
            ),
            int Function(int, int, ffi.Pointer<ffi.Void>, int)
          >('InternetSetOptionW');
      const settingsChanged = 39;
      const refresh = 37;
      setOption(0, settingsChanged, ffi.nullptr, 0);
      setOption(0, refresh, ffi.nullptr, 0);
    } catch (_) {}
  }

  Future<void> _kill() async {
    try {
      _proc?.kill();
    } catch (_) {}
    _proc = null;
    _exitIp = null;
    _activeNodeName = null;
  }

  /// Stops the core and restores the direct connection.
  Future<void> stop() async {
    await _clearSystemProxy();
    await _kill();
  }
}
