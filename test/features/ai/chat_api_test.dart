// The chat client is the single point every AI provider goes through, so its
// error classification decides whether the UI rotates or gives up. Driven
// against a fake transport; no network.
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mide/features/ai/chat_api.dart';

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.respond);

  final ResponseBody Function(RequestOptions options) respond;
  final List<RequestOptions> seen = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    seen.add(options);
    return respond(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _body(Object payload, int status) => ResponseBody.fromString(
  jsonEncode(payload),
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

ResponseBody _answer(String content) => _body({
  'choices': [
    {
      'message': {'content': content},
    },
  ],
}, 200);

OpenAiClient _client(_FakeAdapter adapter) {
  final dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
  dio.httpClientAdapter = adapter;
  return OpenAiClient(dio: dio);
}

const _provider = LlmProvider(
  label: 'Kilo',
  baseUrl: 'https://api.kilo.ai/api/gateway',
  models: ['kilo-auto/free'],
);

void main() {
  group('anonymous request shape', () {
    test('sends no Authorization header when the provider has none', () async {
      final adapter = _FakeAdapter((_) => _answer('привет'));
      final client = _client(adapter);

      await client.chat(
        provider: _provider,
        model: 'kilo-auto/free',
        messages: [
          {'role': 'user', 'content': 'hi'},
        ],
      );

      final headers = adapter.seen.single.headers;
      expect(headers.containsKey('Authorization'), isFalse);
      expect(headers['Content-Type'], 'application/json');
    });

    test('sends the provider user-agent when one is set', () async {
      final adapter = _FakeAdapter((_) => _answer('ok'));
      final client = _client(adapter);

      await client.chat(
        provider: const LlmProvider(
          label: 'Pollinations',
          baseUrl: 'https://text.pollinations.ai',
          models: ['openai'],
          userAgent: 'Mozilla/5.0',
        ),
        model: 'openai',
        messages: [
          {'role': 'user', 'content': 'hi'},
        ],
      );

      expect(adapter.seen.single.headers['User-Agent'], 'Mozilla/5.0');
    });

    test('posts to baseUrl + chatPath', () async {
      final adapter = _FakeAdapter((_) => _answer('ok'));
      await _client(adapter).chat(
        provider: _provider,
        model: 'm',
        messages: [
          {'role': 'user', 'content': 'hi'},
        ],
      );

      final uri = adapter.seen.single.uri;
      expect(
        uri.toString(),
        'https://api.kilo.ai/api/gateway/chat/completions',
      );
    });
  });

  group('placeholder key is skipped without touching the network', () {
    test('needsKey is true only for the placeholder token', () {
      expect(_provider.needsKey, isFalse);
      expect(_provider.withAuth('PASTE_YOUR_HORDE_KEY').needsKey, isTrue);
      expect(_provider.withAuth('0000000000').needsKey, isFalse);
    });

    test('throws a rotatable 401 and never dials out', () async {
      final adapter = _FakeAdapter((_) => _answer('should not happen'));

      await expectLater(
        _client(adapter).chat(
          provider: _provider.withAuth('PASTE_YOUR_HORDE_KEY'),
          model: 'm',
          messages: [
            {'role': 'user', 'content': 'hi'},
          ],
        ),
        throwsA(
          isA<LlmException>()
              .having((e) => e.statusCode, 'statusCode', 401)
              .having(
                (e) => e.message,
                'message',
                contains('нужен бесплатный ключ'),
              ),
        ),
      );
      expect(adapter.seen, isEmpty);
    });
  });

  group('error classification drives rotation', () {
    Future<LlmException> failureFor(ResponseBody Function() respond) async {
      final adapter = _FakeAdapter((_) => respond());
      try {
        await _client(adapter).chat(
          provider: _provider,
          model: 'm',
          messages: [
            {'role': 'user', 'content': 'hi'},
          ],
        );
      } on LlmException catch (e) {
        return e;
      }
      fail('expected a LlmException');
    }

    test('404 means the model id is gone', () async {
      final e = await failureFor(() => _body({'error': 'nope'}, 404));
      expect(e.statusCode, 404);
      expect(e.message, contains('модель не найдена'));
    });

    test('429 is a rate limit', () async {
      final e = await failureFor(() => _body({'error': 'slow down'}, 429));
      expect(e.statusCode, 429);
    });

    test('503 is transient', () async {
      final e = await failureFor(() => _body({'error': 'down'}, 503));
      expect(e.statusCode, 503);
      expect(e.message, contains('временно недоступен'));
    });

    test('a 200 carrying budget text still rotates', () async {
      final e = await failureFor(
        () => _answer('This model has reached its budget for today'),
      );
      expect(e.statusCode, 429);
    });

    test('a 200 with no choices is an empty answer', () async {
      final e = await failureFor(() => _body({'choices': []}, 200));
      expect(e.message, contains('Пустой ответ'));
    });

    test('a network failure is reported, not swallowed', () async {
      final e = await failureFor(
        () => throw DioException(
          requestOptions: RequestOptions(path: '/chat/completions'),
          type: DioExceptionType.connectionError,
          message: 'нет сети',
        ),
      );
      // The provider label is prepended so the user sees which one died.
      expect(e.message, contains('Kilo'));
      expect(e.message.toLowerCase(), contains('нет сети'));
    });
  });

  group('successful answers', () {
    test('returns the message content verbatim', () async {
      final adapter = _FakeAdapter((_) => _answer('короткий ответ'));
      final text = await _client(adapter).chat(
        provider: _provider,
        model: 'm',
        messages: [
          {'role': 'user', 'content': 'hi'},
        ],
      );
      expect(text, 'короткий ответ');
    });

    test('accepts a bare message string some gateways return', () async {
      final adapter = _FakeAdapter(
        (_) => _body({
          'choices': [
            {'message': 'плоский ответ'},
          ],
        }, 200),
      );
      final text = await _client(adapter).chat(
        provider: _provider,
        model: 'm',
        messages: [
          {'role': 'user', 'content': 'hi'},
        ],
      );
      expect(text, 'плоский ответ');
    });
  });
}
