// Persona-scoped AI sessions: each persona owns its own conversation key.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mide/features/ai/ai_model.dart';
import 'package:mide/features/ai/ai_providers.dart';

void main() {
  group('PersonaArg', () {
    test('value equality and hashCode', () {
      const a = PersonaArg(systemPrompt: 'p', chatKey: 'k');
      const b = PersonaArg(systemPrompt: 'p', chatKey: 'k');
      const c = PersonaArg(systemPrompt: 'p', chatKey: 'other');
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });
  });

  group('AiSessionNotifier personas', () {
    const mira = PersonaArg(
      systemPrompt: 'Ты — Мира.',
      chatKey: 'mide_ai_chat_companion_v1',
    );

    test('Ada and a persona are independent providers', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Both build without a device: storage reads fail softly, leaving an
      // empty conversation.
      expect(container.read(aiSessionProvider).messages, isEmpty);
      expect(container.read(personaSessionProvider(mira)).messages, isEmpty);
      expect(container.read(aiSessionProvider).busy, isFalse);
      expect(container.read(personaSessionProvider(mira)).busy, isFalse);
    });

    test('clear resets state and reports idle', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(personaSessionProvider(mira).notifier).clear();
      final s = container.read(personaSessionProvider(mira));
      expect(s.messages, isEmpty);
      expect(s.error, isNull);
      expect(s.busy, isFalse);
    });

    test('state copyWith keeps messages and flags', () {
      const msg = AiMessage(AiRole.user, 'привет');
      const s = AiSessionState(messages: [msg], busy: true);
      final s2 = s.copyWith(busy: false);
      expect(s2.messages, [msg]);
      expect(s2.busy, isFalse);
    });
  });
}
