// Free coding providers for the PC IDE: Kilo → LLM7 → OVHcloud.
// Same LlmProvider/OpenAiClient plumbing as the Ada chat (features/ai),
// but a coding-focused rotation and a longer receive timeout for big
// code answers.
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../ai/chat_api.dart';
import '../ai/ai_model.dart';
import 'ide_providers.dart';

/// Kilo Gateway (https://api.kilo.ai) — free `:free` models. Anonymous
/// access is currently rejected (403) for some networks, so the rotation
/// tries it first and instantly falls through unless the user pasted a
/// free API key (register at https://app.kilo.ai — no card required).
const String ideKiloKeyPlaceholder = 'Bearer PASTE_YOUR_FREE_KILO_KEY';

const LlmProvider kiloProvider = LlmProvider(
  label: 'Kilo',
  baseUrl: 'https://api.kilo.ai/api/gateway',
  models: [
    'kilo-auto/free',
    'minimax/minimax-m2.1:free',
    'z-ai/glm-5:free',
  ],
  authHeader: ideKiloKeyPlaceholder,
);

/// LLM7.io — free keyless gateway (verified working, 2026-09).
const LlmProvider llm7Provider = LlmProvider(
  label: 'LLM7',
  baseUrl: 'https://api.llm7.io/v1',
  models: [
    'minimax-m2.7',
    'DeepSeek-V4-Flash-0731',
    'gemini-3.1-flash-lite',
    'gemma4:31b',
  ],
);

/// OVHcloud AI Endpoints — keyless per-IP rate limit (429 rotates away).
/// Model list refreshed against GET /v1/models (2026-09): Qwen3-32B is
/// gone, coding models Qwen3-Coder / gpt-oss are live.
const LlmProvider ovhProvider = LlmProvider(
  label: 'OVH',
  baseUrl: 'https://oai.endpoints.kepler.ai.cloud.ovh.net/v1',
  models: [
    'Qwen3-Coder-30B-A3B-Instruct',
    'gpt-oss-20b',
    'Qwen3.6-27B',
    'Mistral-Small-3.2-24B-Instruct-2506',
    'Meta-Llama-3_3-70B-Instruct',
  ],
);

/// IDE rotation order: Kilo (free models) → LLM7 → OVHcloud.
const List<LlmProvider> ideCodingProviders = <LlmProvider>[
  kiloProvider,
  llm7Provider,
  ovhProvider,
];

/// (providerIndex, modelIndex) pair in rotation order.
class IdeSlot {
  final int provider;
  final int model;
  const IdeSlot(this.provider, this.model);
}

List<IdeSlot> _ideSlots() {
  final out = <IdeSlot>[];
  for (var p = 0; p < ideCodingProviders.length; p++) {
    for (var m = 0; m < ideCodingProviders[p].models.length; m++) {
      out.add(IdeSlot(p, m));
    }
  }
  return out;
}

/// Free Kilo API key (optional), persisted in secure storage.
final kiloKeyProvider =
    NotifierProvider<_KiloKeyNotifier, String>(_KiloKeyNotifier.new);

class _KiloKeyNotifier extends Notifier<String> {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static const _key = 'mide_kilo_api_key';

  @override
  String build() {
    _load();
    return '';
  }

  Future<void> _load() async {
    try {
      final v = await _storage.read(key: _key);
      if (v != null && v.isNotEmpty) state = v;
    } catch (_) {
      // Non-fatal: Kilo fast-skips without a key.
    }
  }

  Future<void> set(String key) async {
    final v = key.trim();
    state = v;
    try {
      if (v.isEmpty) {
        await _storage.delete(key: _key);
      } else {
        await _storage.write(key: _key, value: v);
      }
    } catch (_) {
      // Non-fatal: key applies for this session anyway.
    }
  }

  Future<void> clear() => set('');
}

// ── Coding session ─────────────────────────────────────────────────────────

const String _ideSystemPrompt =
    'Ты — встроенный программист-ассистент внутри IDE на ПК. Отвечай на '
    'языке пользователя, кратко и по делу. Код всегда давай в блоках ``` с '
    'указанием языка. Если приложен открытый файл — работай именно с ним.';

class IdeAiState {
  final List<AiMessage> messages;
  final bool busy;
  final String? error;

  /// Label of the provider currently in play («Kilo» / «LLM7» / «OVH»).
  final String providerLabel;

  const IdeAiState({
    this.messages = const [],
    this.busy = false,
    this.error,
    this.providerLabel = 'Kilo',
  });

  IdeAiState copyWith({
    List<AiMessage>? messages,
    bool? busy,
    String? error,
    bool clearError = false,
    String? providerLabel,
  }) =>
      IdeAiState(
        messages: messages ?? this.messages,
        busy: busy ?? this.busy,
        error: clearError ? null : (error ?? this.error),
        providerLabel: providerLabel ?? this.providerLabel,
      );
}

class IdeAiNotifier extends Notifier<IdeAiState> {
  /// Long receive timeout — code answers are big and non-streaming.
  late final OpenAiClient _client = OpenAiClient(
    dio: Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 90),
      ),
    ),
  );

  CancelToken? _token;
  bool _cancelled = false;
  int _lastSlot = 0;

  @override
  IdeAiState build() {
    ref.onDispose(() => _token?.cancel());
    return const IdeAiState();
  }

  void cancel() {
    _cancelled = true;
    _token?.cancel();
    _token = null;
    state = state.copyWith(busy: false, clearError: true);
  }

  /// Sends [question] with the active file attached as context and rotates
  /// across Kilo → LLM7 → OVH until one answers.
  Future<void> ask(String question) async {
    final q = question.trim();
    if (q.isEmpty || state.busy) return;
    _cancelled = false;

    final userMsg = AiMessage(AiRole.user, q);
    state = state.copyWith(
      messages: [...state.messages, userMsg],
      busy: true,
      clearError: true,
    );

    // Context: active editor buffer (capped so prompts stay reasonable).
    final tab = ref.read(ideTabsProvider).activeTab;
    final contextBlock = tab == null
        ? ''
        : '\n\nОткрытый файл: ${tab.path}\n```'
            '${_ideLangHint(tab.path)}\n'
            '${tab.content.length > 14000 ? tab.content.substring(0, 14000) : tab.content}'
            '\n```';

    final history = <Map<String, String>>[
      {'role': 'system', 'content': _ideSystemPrompt},
      for (final m in state.messages)
        if (m.text.isNotEmpty)
          {
            'role': m.role == AiRole.user ? 'user' : 'assistant',
            'content': m.text,
          },
    ];
    // Attach the file only to the latest user turn.
    history[history.length - 1] = {
      'role': 'user',
      'content': '$q$contextBlock',
    };

    final slots = _ideSlots();
    final kiloKey = ref.read(kiloKeyProvider).trim();

    for (var i = 0; i < slots.length; i++) {
      final slot = slots[(_lastSlot + i) % slots.length];
      final provider = ideCodingProviders[slot.provider];
      final model = provider.models[slot.model];

      // Inject the persisted Kilo key at request time (placeholder fast-skip
      // stays in place when the user has not pasted one yet).
      final effective = provider.label == 'Kilo'
          ? provider.withAuth(
              kiloKey.isEmpty ? ideKiloKeyPlaceholder : 'Bearer $kiloKey',
            )
          : provider;

      state = state.copyWith(providerLabel: effective.label);
      _token = CancelToken();
      try {
        final answer = await _client.chat(
          provider: effective,
          model: model,
          messages: history,
          cancelToken: _token,
        );
        if (_cancelled) return;
        _lastSlot = slot.provider;
        _appendAssistant(answer);
        state = state.copyWith(busy: false, clearError: true);
        return;
      } on LlmException catch (e) {
        if (_cancelled) return;
        if (e.statusCode == null) {
          // Network-level failure — no point rotating.
          _fail('Нет сети. Проверь подключение.');
          return;
        }
        // Per-slot failure (403/404/429…) — rotate to the next model.
        continue;
      } catch (_) {
        if (_cancelled) return;
        _fail('Ассистент недоступен, попробуй позже.');
        return;
      }
    }
    if (!_cancelled) {
      _fail('Все бесплатные провайдеры заняты (Kilo/OVH/LLM7). Повтори позже.');
    }
  }

  void _appendAssistant(String text) {
    state = state.copyWith(
      messages: [...state.messages, AiMessage(AiRole.assistant, text)],
    );
  }

  void _fail(String message) {
    state = state.copyWith(busy: false, error: message);
  }

  void clearError() => state = state.copyWith(clearError: true);
}

/// Language hint for a ``` fence based on the file extension.
String _ideLangHint(String path) {
  switch (_extOf(path)) {
    case '.dart':
      return 'dart';
    case '.py':
      return 'python';
    case '.js':
    case '.mjs':
      return 'javascript';
    case '.ts':
      return 'typescript';
    case '.json':
      return 'json';
    case '.html':
      return 'html';
    case '.css':
      return 'css';
    case '.sh':
      return 'bash';
    case '.ps1':
      return 'powershell';
    case '.kt':
      return 'kotlin';
    case '.java':
      return 'java';
    case '.c':
    case '.h':
      return 'c';
    case '.cpp':
    case '.hpp':
      return 'cpp';
    case '.cs':
      return 'csharp';
    case '.go':
      return 'go';
    case '.rs':
      return 'rust';
    case '.sql':
      return 'sql';
    case '.md':
      return 'markdown';
    case '.yaml':
    case '.yml':
      return 'yaml';
    default:
      return '';
  }
}

String _extOf(String path) {
  final name = path.replaceAll('\\', '/').split('/').last;
  final i = name.lastIndexOf('.');
  return i <= 0 ? '' : name.substring(i).toLowerCase();
}

final ideAiProvider =
    NotifierProvider<IdeAiNotifier, IdeAiState>(IdeAiNotifier.new);


