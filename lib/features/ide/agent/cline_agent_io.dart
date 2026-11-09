// Desktop bridge to the Mide AGI sidecar (agent/src/index.mjs, Cline SDK).
// Flow: find node.exe + agent/ → spawn `node src/index.mjs` with WORKSPACE of
// the open project → wait for /health → drive /chat (SSE) and answer tool
// approvals through /approve. Killing the tile kills the child, nothing else.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'cline_agent_models.dart';

export 'cline_agent_models.dart';

class ClineAgentBackend {
  ClineAgentBackend._();
  static final ClineAgentBackend instance = ClineAgentBackend._();

  static bool get isSupported => true;

  Process? _proc;
  HttpClient? _http;
  int _port = 0;
  String _log = '';
  ClineAgentInfo? _info;
  final _events = StreamController<ClineAgentEvent>.broadcast();

  bool get isRunning => _proc != null;
  ClineAgentInfo? get info => _info;
  Stream<ClineAgentEvent> get events => _events.stream;

  /// Boot the sidecar for [workspace]. Throws [ClineAgentException] with a
  /// human-readable reason (no node, no agent folder, unhealthy child).
  Future<ClineAgentInfo> start({
    required String workspace,
    String? nodePath,
  }) async {
    if (_proc != null && _info != null) return _info!;
    final script = _agentScript();
    if (script == null) {
      throw const ClineAgentException(
        'Папка agent/ с Cline-сайдкаром не найдена. Открой проект, в котором '
        'есть agent/src/index.mjs (или npm install внутри agent/).',
      );
    }
    final node = nodePath?.trim();
    final exe = node == null || node.isEmpty ? 'node' : node;
    _port = await _freePort();
    _log = '';

    Process proc;
    try {
      proc = await Process.start(
        exe,
        [script.path],
        workingDirectory: script.parent.parent.path,
        environment: {
          'AGENT_PORT': '$_port',
          'WORKSPACE': workspace,
          'PROVIDER': 'openai-compatible',
          'BASE_URL': kClineAgentBaseUrl,
          'MODEL': kClineAgentModel,
        },
      );
    } on ProcessException catch (e) {
      throw ClineAgentException(
        // ProcessException exposes the OS code as `errorCode` (there is no
        // `osError` on it) — 2 == ENOENT, i.e. node is not on PATH.
        e.errorCode == 2
            ? 'Node.js не найден ($exe). Укажи путь к node.exe в ⚙ «Инструменты».'
            : 'Не удалось запустить агент: ${e.message}',
      );
    }
    _proc = proc;
    proc.stdout.transform(const Utf8Decoder(allowMalformed: true)).listen(_onChildLine);
    proc.stderr.transform(const Utf8Decoder(allowMalformed: true)).listen(_onChildLine);

    final info = await _waitHealth();
    _info = info;
    unawaited(proc.exitCode.then((code) {
      if (_port != 0) _port = 0;
      _proc = null;
      _info = null;
      _events.add(ClineAgentEvent(
        type: 'stopped',
        text: 'Сайдкар завершился (код $code)',
        status: code.toString(),
      ));
    }));
    return info;
  }

  void _onChildLine(String raw) {
    for (final line in const LineSplitter().convert(raw)) {
      if (line.trim().isEmpty) continue;
      _log = '${_log}\n$line'.split('\n').take(60).join('\n');
    }
  }

  /// Send [message] to the agent and re-publish every SSE event.
  Future<void> send(String message) async {
    final http = _httpClient();
    try {
      final req = await http.post('127.0.0.1', _port, '/chat');
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode({'message': message}));
      final res = await req.close();
      await for (final line in res.transform(const Utf8Decoder(allowMalformed: true)).transform(const LineSplitter())) {
        if (!line.startsWith('data: ')) continue;
        final ev = _decode(line.substring(6));
        if (ev == null) continue;
        final out = ev['output'];
        _events.add(ClineAgentEvent(
          type: '${ev['type']}',
          // tool_end carries `output`, done carries `error` — both belong in
          // the transcript text, so fold them into one field here.
          text: ev['text'] is String
              ? ev['text'] as String
              : out != null
                  ? (out is String ? out : '$out')
                  : ev['error'] is String
                      ? ev['error'] as String
                      : null,
          name: ev['name'] is String ? ev['name'] as String : null,
          input: ev['input'],
          approvalId: ev['id'] is String ? ev['id'] as String : null,
          status: ev['status'] is String ? ev['status'] as String : null,
        ));
      }
    } on SocketException catch (e) {
      _events.add(ClineAgentEvent(type: 'error', text: 'Сайдкар недоступен: ${e.osError?.message ?? e.message}'));
      rethrow;
    } catch (e) {
      _events.add(ClineAgentEvent(type: 'error', text: 'Связь с агентом потеряна: $e'));
      rethrow;
    } finally {
      http.close(force: true);
    }
  }

  /// Answer a pending tool approval.
  Future<void> approve(String id, bool ok) =>
      _post('/approve', {'id': id, 'ok': ok});

  Future<void> interrupt() => _post('/stop', const {});

  Future<void> reset() => _post('/reset', const {});

  /// Stop the child we started (only ours — never somebody else's node).
  Future<void> shutdown() async {
    final proc = _proc;
    _proc = null;
    _info = null;
    _port = 0;
    if (proc == null) return;
    proc.kill(ProcessSignal.sigterm);
    try {
      await proc.exitCode.timeout(const Duration(seconds: 3));
    } on TimeoutException {
      proc.kill(ProcessSignal.sigkill);
    }
  }

  Future<void> _post(String path, Map<String, Object?> body) async {
    if (_port == 0) return;
    final http = _httpClient();
    try {
      final req = await http.post('127.0.0.1', _port, path);
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(body));
      await (await req.close()).drain<void>();
    } finally {
      http.close(force: true);
    }
  }

  HttpClient _httpClient() =>
      _http ??= HttpClient()..connectionTimeout = const Duration(seconds: 5);

  Future<ClineAgentInfo> _waitHealth() async {
    final http = _httpClient();
    final deadline = DateTime.now().add(const Duration(seconds: 25));
    while (DateTime.now().isBefore(deadline)) {
      if (_proc == null) break;
      try {
        // `HttpClient.get` hands back the *request*; the body only arrives
        // after `close()` returns the response.
        final req = await http
            .get('127.0.0.1', _port, '/health')
            .timeout(const Duration(seconds: 2));
        final body = await (await req.close()).transform(utf8.decoder).join();
        final j = _decode(body);
        if (j != null && j['ok'] == true) {
          return ClineAgentInfo(
            model: '${j['model']}',
            provider: '${j['provider']}',
            port: _port,
            tools: [
              for (final t in (j['tools'] as List? ?? const [])) '$t',
            ],
            workspace: '${j['workspace']}',
          );
        }
      } catch (_) {
        // Not listening yet — the child is still booting.
      }
      await Future.delayed(const Duration(milliseconds: 300));
    }
    final tail = _log.trim();
    _proc?.kill();
    _proc = null;
    throw ClineAgentException(tail.isEmpty
        ? 'Агент не поднялся за 25 с — проверь, что node.exe целая установка.'
        : 'Агент не поднялся: ${tail.split('\n').take(6).join(' / ')}');
  }

  /// A port nobody holds: two IDE windows must not fight over 8765.
  static Future<int> _freePort() async {
    final srv = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = srv.port;
    await srv.close();
    return port;
  }

  /// Locate `agent/src/index.mjs`: explicit env override, cwd, then walking up
  /// from the executable (dev builds live in build/windows/…/Debug).
  static File? _agentScript() {
    for (final root in _searchRoots()) {
      var dir = Directory(root);
      for (var depth = 0; depth < 6 && dir.existsSync(); depth++) {
        final asAgentDir = File(_join(dir.path, 'src', 'index.mjs'));
        if (asAgentDir.existsSync()) return asAgentDir;
        final nested = File(_join(dir.path, 'agent', 'src', 'index.mjs'));
        if (nested.existsSync()) return nested;
        dir = dir.parent;
      }
    }
    return null;
  }

  static Iterable<String> _searchRoots() => [
        if (Platform.environment['MIDE_AGENT_DIR']?.trim().isNotEmpty ?? false)
          Platform.environment['MIDE_AGENT_DIR']!.trim(),
        Directory.current.path,
        File(Platform.resolvedExecutable).parent.path,
      ];

  static String _join(String a, String b, [String c = '', String d = '']) =>
      <String>[a, b, c, d].where((p) => p.isNotEmpty).join(Platform.pathSeparator);

  static Map<String, Object?>? _decode(String body) {
    try {
      final v = jsonDecode(body);
      return v is Map<String, Object?> ? v : null;
    } catch (_) {
      return null;
    }
  }
}
