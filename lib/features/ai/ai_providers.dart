// Ada (M.AI) chat session вЂ” rotates across Horde + Pollinations + LLM7 +
// OVH. Non-streaming call; while waiting the UI shows a red thinking-blink,
// then the full answer fades in. The Horde API key (free, from
// stablehorde.net) is persisted separately and injected at request time;
// without it the Horde slots fast-skip and the answer comes from an
// anonymous provider.
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'ai_model.dart';
import 'chat_api.dart';
import 'providers_registry.dart';

/// The single user-visible error phrase for any AI failure.
const String aiBusyPhrase = 'РђРґР° Р·Р°РЅСЏС‚Р°, РїРѕРїСЂРѕР±СѓР№ РїРѕР·Р¶Рµ!';

class AiSessionState {
  final List<AiMessage> messages;
  final String? error;
  final bool busy;
  final bool streaming;

  /// Label of the provider currently "in play" (drives the LLM7в†”OVH badge).
  final String providerLabel;

  const AiSessionState({
    this.messages = const [],
    this.error,
    this.busy = false,
    this.streaming = false,
    this.providerLabel = 'Pollinations',
  });

  AiSessionState copyWith({
    List<AiMessage>? messages,
    String? error,
    bool? clearError,
    bool? busy,
    bool? streaming,
    String? providerLabel,
  }) =>
      AiSessionState(
        messages: messages ?? this.messages,
        error: clearError == true ? null : (error ?? this.error),
        busy: busy ?? this.busy,
        streaming: streaming ?? this.streaming,
        providerLabel: providerLabel ?? this.providerLabel,
      );
}

class AiSessionNotifier extends Notifier<AiSessionState> {
  static const _systemPrompt =
      'РўС‹ вЂ” РђРґР°. РћС‚РІРµС‡Р°Р№ РјР°РєСЃРёРјР°Р»СЊРЅРѕ РєРѕСЂРѕС‚РєРѕ (1вЂ“3 РїСЂРµРґР»РѕР¶РµРЅРёСЏ), РїРѕ РґРµР»Сѓ, РІ СЏР·С‹РєРµ РїРѕР»СЊР·РѕРІР°С‚РµР»СЏ.';

  final OpenAiClient _client = OpenAiClient();
  CancelToken? _token;
  bool _cancelled = false;

  /// Last slot in [allSlots] that actually answered.
  int _lastSlot = 0;

  /// Chat persistence: the last 1000 messages survive app restarts so the
  /// conversation is never wiped when the app reopens.
  static const _chatStore = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static const _chatKey = 'mide_ai_chat_v1';
  static const _maxMessages = 1000;

  @override
  AiSessionState build() {
    ref.onDispose(() => _token?.cancel());
    _loadChat();
    return const AiSessionState();
  }

  /// Restores the saved conversation (capped to the most recent messages).
  Future<void> _loadChat() async {
    try {
      final raw = await _chatStore.read(key: _chatKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw) as List;
      final msgs = <AiMessage>[
        for (final e in decoded)
          AiMessage(
            e is Map && e['role'] == 'assistant' ? AiRole.assistant : AiRole.user,
            e is Map ? (e['text'] as String? ?? '') : '',
          ),
      ];
      if (_cancelled) return;
      if (msgs.any((m) => m.text.isNotEmpty)) {
        state = state.copyWith(messages: msgs, streaming: false, busy: false);
      }
    } catch (_) {
      // Corrupt payload — start clean rather than crash.
    }
  }

  /// Persists the conversation (capped at 1000 messages) for next launch.
  Future<void> _persistChat() async {
    final msgs = state.messages.where((m) => m.text.isNotEmpty).toList();
    try {
      if (msgs.isEmpty) {
        await _chatStore.delete(key: _chatKey);
        return;
      }
      final tail =
          msgs.length > _maxMessages ? msgs.sublist(msgs.length - _maxMessages) : msgs;
      await _chatStore.write(
        key: _chatKey,
        value: jsonEncode([
          for (final m in tail)
            {'role': m.role == AiRole.user ? 'user' : 'assistant', 'text': m.text},
        ]),
      );
    } catch (_) {
      // Best-effort persistence; the live session is unaffected.
    }
  }

  void cancel() {
    _cancelled = true;
    _token?.cancel();
    _token = null;
    final messages = state.messages;
    if (messages.isNotEmpty && messages.last.role == AiRole.assistant) {
      final last = messages.last;
      state = state.copyWith(
        messages: last.text.isEmpty
            ? messages.sublist(0, messages.length - 1)
            : [
                ...messages.sublist(0, messages.length - 1),
                last.copyWith(streaming: false),
              ],
        busy: false,
        streaming: false,
      );
      return;
    }
    state = state.copyWith(busy: false, streaming: false);
  }

  void send(String question) {
    final text = question.trim();
    if (text.isEmpty || state.busy) return;
    _cancelled = false;
    state = state.copyWith(
      messages: [
        ...state.messages,
        AiMessage(AiRole.user, text),
        const AiMessage(AiRole.assistant, '', streaming: true),
      ],
      busy: true,
      streaming: true,
      clearError: true,
    );
    _persistChat();
    _run();
  }

  List<Map<String, String>> _messages() {
    return [
      {'role': 'system', 'content': _systemPrompt},
      ...state.messages
          .where((m) => m.text.isNotEmpty)
          .map((m) => {
                'role': m.role == AiRole.user ? 'user' : 'assistant',
                'content': m.text,
              }),
    ];
  }

  Future<void> _run() async {
    _token = CancelToken();
    final msgs = _messages();
    final result = await _fetchAnswer(msgs);
    if (result == null) return; // failure handled inside
    final answer = result.$1;
    final providerLabel = result.$2;
    // Reflect which provider is answering in the badge.
    state = state.copyWith(providerLabel: providerLabel);
    await _reveal(answer);
  }

  /// Rotates across every (provider, model) slot until one returns an answer.
  Future<(String, String)?> _fetchAnswer(List<Map<String, String>> msgs) async {
    final slots = allSlots;
    final hordeKey = ref.read(hordeKeyProvider).trim();
    for (var attempt = 0; attempt < slots.length; attempt++) {
      if (_cancelled) return null;
      final idx = (_lastSlot + attempt) % slots.length;
      final slot = slots[idx];
      var provider = providers[slot.providerIndex];
      // Inject the user's persisted Horde key so the top provider actually
      // works once a free stablehorde.net key has been added.
      if (provider.label == 'Horde' && hordeKey.isNotEmpty) {
        provider = provider.withAuth('Bearer $hordeKey');
      }
      final model = provider.models[slot.modelIndex];
      try {
        final text = await _client.chat(
          provider: provider,
          model: model,
          messages: msgs,
          cancelToken: _token,
        );
        if (text.trim().isNotEmpty) {
          _lastSlot = idx;
          return (text, provider.label);
        }
      } on DioException catch (e) {
        if (e.type == DioExceptionType.cancel || _cancelled) return null;
        // Network-level failure вЂ” no point burning the whole rotation.
        _finish(errorText: aiBusyPhrase);
        return null;
      } on LlmException {
        // Per-slot failure вЂ” remember it and rotate to the next slot so
        // the next question starts past the broken provider/model instead
        // of waiting for the slow queue again.
        _lastSlot = idx;
        continue;
      } catch (_) {
        _finish(errorText: aiBusyPhrase);
        return null;
      }
    }
    _finish(errorText: aiBusyPhrase);
    return null;
  }

  /// Fills the pending assistant message with the full answer. The UI
  /// handles the smooth reveal (the "thinking" blinking underscore swaps to
  /// the finished answer on its own).
  Future<void> _reveal(String answer) async {
    if (_cancelled) {
      _finish(errorText: null);
      return;
    }
    _setLastAssistant(answer, streaming: false);
    _finish(errorText: null);
  }

  void _setLastAssistant(String text, {required bool streaming}) {
    final messages = state.messages;
    if (messages.isEmpty || messages.last.role != AiRole.assistant) return;
    state = state.copyWith(
      messages: [
        ...messages.sublist(0, messages.length - 1),
        messages.last.copyWith(text: text, streaming: streaming),
      ],
    );
  }

  void _finish({required String? errorText}) {
    _token = null;
    final messages = state.messages;
    if (messages.isEmpty || messages.last.role != AiRole.assistant) {
      state = state.copyWith(busy: false, streaming: false, error: errorText);
      return;
    }
    final last = messages.last;
    if (last.text.isEmpty) {
      state = state.copyWith(
        messages: messages.sublist(0, messages.length - 1),
        error: errorText,
        busy: false,
        streaming: false,
      );
      _persistChat();
      return;
    }
    state = state.copyWith(
      messages: [
        ...messages.sublist(0, messages.length - 1),
        last.copyWith(streaming: false),
      ],
      error: errorText,
      busy: false,
      streaming: false,
    );
    _persistChat();
  }
}

final aiSessionProvider =
    NotifierProvider<AiSessionNotifier, AiSessionState>(AiSessionNotifier.new);

// в”Ђв”Ђ Horde API key (free from stablehorde.net), persisted in secure storage в”Ђ

final hordeKeyProvider =
    NotifierProvider<_HordeKeyNotifier, String>(_HordeKeyNotifier.new);

class _HordeKeyNotifier extends Notifier<String> {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static const _key = 'mide_horde_api_key';

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
      // Non-fatal: key stays empty (Horde slots fast-skip).
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
      // Non-fatal: key still applies for this session.
    }
  }

  Future<void> clear() => set('');
}

