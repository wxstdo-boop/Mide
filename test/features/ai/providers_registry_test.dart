// Tests for the provider registry and the shared OpenAI-compatible client.
import 'package:flutter_test/flutter_test.dart';
import 'package:mide/features/ai/chat_api.dart';
import 'package:mide/features/ai/providers_registry.dart';

void main() {
  group('LlmProvider', () {
    test('needsKey is true only for the un-filled placeholder', () {
      const placeholder = LlmProvider(
        label: 'Horde',
        baseUrl: 'https://x/v1',
        models: ['m'],
        authHeader: 'Bearer PASTE_YOUR_HORDE_API_KEY',
      );
      const filled = LlmProvider(
        label: 'Horde',
        baseUrl: 'https://x/v1',
        models: ['m'],
        authHeader: 'Bearer real-token',
      );
      const keyless = LlmProvider(
        label: 'OVH',
        baseUrl: 'https://x/v1',
        models: ['m'],
      );
      expect(placeholder.needsKey, isTrue);
      expect(filled.needsKey, isFalse);
      expect(keyless.needsKey, isFalse);
    });

    test('withAuth swaps only the auth header', () {
      final p = pollinations.withAuth('Bearer tok');
      expect(p.authHeader, 'Bearer tok');
      expect(p.label, pollinations.label);
      expect(p.baseUrl, pollinations.baseUrl);
      expect(p.userAgent, pollinations.userAgent);
      expect(p.models, pollinations.models);
    });

    test('chatPath defaults to chat/completions', () {
      expect(horde.chatPath, 'chat/completions');
      expect(pollinations.chatPath, 'openai');
    });
  });

  group('provider rotation', () {
    test('allSlots covers every provider/model pair in order', () {
      final slots = allSlots;
      final expected = providers.fold<int>(0, (n, p) => n + p.models.length);
      expect(slots.length, expected);
      // First slot points at the first provider's first model.
      expect(slots.first.providerIndex, 0);
      expect(slots.first.modelIndex, 0);
      // Ordering: provider index is non-decreasing across slots.
      for (var i = 1; i < slots.length; i++) {
        expect(
          slots[i].providerIndex,
          greaterThanOrEqualTo(slots[i - 1].providerIndex),
        );
      }
    });

    test('the placeholder-key Horde provider is last in rotation', () {
      expect(providers.last.label, 'Horde');
      expect(providers.last.needsKey, isTrue);
    });
  });

  group('OpenAiClient fast-skip', () {
    test(
      'throws 401 without touching the network when a key is missing',
      () async {
        final client = OpenAiClient();
        await expectLater(
          client.chat(
            provider: horde,
            model: horde.models.first,
            messages: const [
              {'role': 'user', 'content': 'hi'},
            ],
          ),
          throwsA(
            isA<LlmException>().having((e) => e.statusCode, 'statusCode', 401),
          ),
        );
      },
    );
  });
}
