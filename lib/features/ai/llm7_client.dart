// LLM7.io — free OpenAI-compatible LLM provider (anonymous, no key).
//
// Base URL: https://api.llm7.io/v1
// Non-streaming: a single POST returns the full answer. The UI reveals
// words locally for a smooth "typing" effect.
import 'package:dio/dio.dart';

/// The single model label shown in the UI (no per-model picker).
const String llm7Label = 'LLM7';

/// Internal rotation order. First entry is the confirmed-anonymous model, so
/// the very first request already works without any key. On a per-model error
/// the client moves to the next entry; the last working index is remembered.
const List<String> llm7Rotation = <String>[
  'minimax-m2.7',
  'DeepSeek-V4-Flash-0731',
  'gemini-3.1-flash-lite',
  'gemma4:31b',
];

class Llm7Exception implements Exception {
  final String message;
  final int? statusCode;

  const Llm7Exception(this.message, {this.statusCode});

  @override
  String toString() => message;
}

class Llm7Client {
  Llm7Client({Dio? dio})
      : _dio =
            dio ?? Dio(BaseOptions(connectTimeout: const Duration(seconds: 10)));

  static const String baseUrl = 'https://api.llm7.io/v1';

  final Dio _dio;

  /// Non-streaming chat completion for a specific model.
  /// Returns the full answer text.
  Future<String> chat({
    required String model,
    required List<Map<String, String>> messages,
    CancelToken? cancelToken,
  }) async {
    final body = <String, dynamic>{
      'model': model,
      'messages': messages,
      'temperature': 0.7,
    };

    final Response<dynamic> response;
    try {
      response = await _dio.post<dynamic>(
        '$baseUrl/chat/completions',
        data: body,
        options: Options(
          responseType: ResponseType.json,
          validateStatus: (s) => s == null || s < 500,
          headers: <String, dynamic>{
            'Content-Type': 'application/json',
          },
        ),
        cancelToken: cancelToken,
      );
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        rethrow;
      }
      throw Llm7Exception(
        _friendlyError(e.response?.statusCode, e.message),
        statusCode: e.response?.statusCode,
      );
    } catch (e) {
      throw Llm7Exception('Нет сети: $e');
    }

    if (response.statusCode != 200) {
      throw Llm7Exception(
        _friendlyError(response.statusCode, null),
        statusCode: response.statusCode,
      );
    }

    // Parse: choices[0].message.content
    final data = response.data;
    if (data is Map<String, dynamic>) {
      final choices = data['choices'];
      if (choices is List && choices.isNotEmpty) {
        final msg = choices.first;
        if (msg is Map && msg['message'] is Map) {
          final content = (msg['message'] as Map)['content'];
          if (content is String) return content;
        }
      }
      // Some providers put "message" directly under choice.
      if (choices is List && choices.isNotEmpty) {
        final msg = choices.first;
        if (msg is Map && msg['message'] is String) {
          return msg['message'] as String;
        }
      }
    }
    throw const Llm7Exception('Пустой ответ от LLM7');
  }

  static String _friendlyError(int? code, String? dioMsg) {
    switch (code) {
      case 401:
        return '401: нужен ключ';
      case 403:
        return '403: нет доступа';
      case 404:
        return '404: модель не найдена';
      case 429:
        return 'Лимит LLM7 — подожди минуту.';
      case 500:
      case 502:
      case 503:
        return 'LLM7 временно недоступен — повтори через минуту.';
      default:
        return dioMsg?.isEmpty == true
            ? 'Не удалось получить ответ LLM7.'
            : 'LLM7: ${dioMsg ?? code.toString()}';
    }
  }
}
