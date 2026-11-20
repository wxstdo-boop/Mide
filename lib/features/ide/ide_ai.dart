// Free coding providers for the PC IDE: Kilo (anonymous) → Pollinations →
// AI Horde. Same LlmProvider/OpenAiClient plumbing as the AI chat
// (features/ai), but a coding-focused rotation and a longer receive timeout
// for big code answers.
//
// LLM7 and OVHcloud were dropped after probing (2026-11): LLM7 answers 401
// "Missing API key" on every model, and the OVH endpoint fails the TLS
// handshake outright.
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../ai/chat_api.dart';
import '../ai/ai_model.dart';
import '../ai/providers_registry.dart';
import 'ide_providers.dart';

/// Kilo Gateway (https://api.kilo.ai) — free `:free` models that answer
/// *without* an Authorization header. Sending the old placeholder token
/// produced a hard 401, so the header is now omitted unless the user pastes
/// a real key from https://app.kilo.ai (no card required, only raises
/// limits).
const String ideKiloKeyPlaceholder = 'Bearer PASTE_YOUR_FREE_KILO_KEY';

/// Only ids that answered a live request (2026-11) belong here. Kilo's free
/// catalogue churns, and a dead id costs a rotation slot on every message
/// before the request even reaches a working model. `minimax/minimax-m2.1`
/// and `z-ai/glm-5` were removed after returning 404 "model does not exist".
const LlmProvider kiloProvider = LlmProvider(
  label: 'Kilo',
  baseUrl: 'https://api.kilo.ai/api/gateway',
  models: [
    'kilo-auto/free',
    'nvidia/nemotron-3-ultra-550b-a55b:free',
    'nvidia/nemotron-3.5-lightning:free',
  ],
);

/// IDE rotation order: Kilo (anonymous) → Pollinations → AI Horde.
/// The last two are the same anonymous endpoints the AI chat uses, so the
/// IDE keeps answering when Kilo is rate-limited.
const List<LlmProvider> ideCodingProviders = <LlmProvider>[
  kiloProvider,
  pollinations,
  horde,
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
final kiloKeyProvider = NotifierProvider<_KiloKeyNotifier, String>(
  _KiloKeyNotifier.new,
);

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

  /// Label of the provider currently in play («Kilo» / «Pollinations» / «Horde»).
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
  }) => IdeAiState(
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
  /// across Kilo → Pollinations → Horde until one answers.
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

      // Kilo answers anonymously; only attach an Authorization header once
      // the user has pasted a real key (the placeholder was a hard 401).
      final effective = provider.label == 'Kilo' && kiloKey.isNotEmpty
          ? provider.withAuth('Bearer $kiloKey')
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
      _fail(
        'Все бесплатные провайдеры заняты (Kilo/Pollinations/Horde). Повтори позже.',
      );
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

final ideAiProvider = NotifierProvider<IdeAiNotifier, IdeAiState>(
  IdeAiNotifier.new,
);
