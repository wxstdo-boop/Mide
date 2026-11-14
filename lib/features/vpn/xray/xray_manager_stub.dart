// Web stub — the Xray sidecar only exists on desktop platforms with a
// process layer. Same public surface as xray_manager_io.dart.
import 'xray_node.dart';

export 'xray_node.dart';

class XrayNodeSource {
  static Future<List<XrayNode>> fetch({
    int limit = 250,
    bool reality = false,
  }) async =>
      throw const XrayException('V2Nodes-движок недоступен в Web-сборке');

  static Future<bool> tcpAlive(XrayNode n, {int timeoutMs = 2500}) async =>
      false;

  static Future<bool> handshakeAlive(
    XrayNode n, {
    int timeoutMs = 5000,
  }) async => false;

  static Future<List<XrayNode>> screen(
    List<XrayNode> nodes, {
    int want = 4,
    int maxScan = 72,
  }) async => const [];
}

class XrayManager {
  XrayManager._();
  static final XrayManager instance = XrayManager._();

  static bool get isSupported => false;
  bool get isRunning => false;
  String? get exitIp => null;
  String? get activeNodeName => null;

  Future<void> ensureCore() async =>
      throw const XrayException('Xray-движок недоступен в Web-сборке');
  Future<void> start({int maxTries = 6, bool reality = false}) async =>
      throw const XrayException('Xray-движок недоступен в Web-сборке');
  Future<void> stop() async {}
}
