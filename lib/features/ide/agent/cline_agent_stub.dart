// Web/mobile stub for the Cline sidecar bridge: no process, no sockets.
import 'cline_agent_models.dart';

export 'cline_agent_models.dart';

class ClineAgentBackend {
  ClineAgentBackend._();
  static final ClineAgentBackend instance = ClineAgentBackend._();

  static bool get isSupported => false;

  bool get isRunning => false;
  ClineAgentInfo? get info => null;
  Stream<ClineAgentEvent> get events => const Stream<ClineAgentEvent>.empty();

  Future<ClineAgentInfo> start({required String workspace, String? nodePath}) async =>
      throw const ClineAgentException(
          'Полноценный агент работает только на ПК (нужен Node.js).');

  Future<void> send(String message) async {}
  Future<void> approve(String id, bool ok) async {}
  Future<void> interrupt() async {}
  Future<void> reset() async {}
  Future<void> shutdown() async {}
}
