// Shared OpenAI-compatible chat client (non-streaming, anonymous).
// Supports multiple providers: LLM7, OVH, Horde, Pollinations.
import 'package:dio/dio.dart';

/// Exception carrying a status code so the rotation layer can decide
/// whether to rotate to the next model/provider or give up.
class LlmException implements Exception {
  final String message;
  final int? statusCode;

  const LlmException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

/// One provider (base URL + label + model list + optional auth).
class LlmProvider {
  final String label; // "Horde", "Pollinations", "LLM7", "OVH"
  final String baseUrl; // without trailing slash, e.g. https://api.llm7.io/v1
  final List<String> models;

  /// Optional auth header value (for providers that require a token).
  final String? authHeader;

  /// Optional user-agent override (for providers that block default UAs).
  final String? userAgent;

  /// Path suffix for chat completions. Defaults to /chat/completions.
  final String chatPath;

  const LlmProvider({
    required this.label,
    required this.baseUrl,
    required this.models,
    this.authHeader,
    this.userAgent,
    this.chatPath = 'chat/completions',
  });

  /// Returns a copy with a (possibly new) auth header. Used to inject the
  /// user's persisted Horde API key at runtime.
  LlmProvider withAuth(String? authHeader) => LlmProvider(
    label: label,
    baseUrl: baseUrl,
    models: models,
    authHeader: authHeader,
    userAgent: userAgent,
    chatPath: chatPath,
  );

  /// True when this provider needs a key that hasn't been filled in yet
  /// (still the placeholder). The rotation fast-skips such providers.
  bool get needsKey {
    final a = authHeader;
    return a != null && a.contains('PASTE_YOUR');
  }
}

class OpenAiClient {
  OpenAiClient({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 8),
              // Queue-based providers (Horde) can stall. A tight receive
              // timeout makes the rotation fall back to the next provider
              // quickly instead of hanging for 25s per model.
              receiveTimeout: const Duration(seconds: 15),
            ),
          );

  final Dio _dio;

  /// Non-streaming chat completion. Returns the full answer text.
  /// Uses the provider's auth/user-agent settings.
  Future<String> chat({
    required LlmProvider provider,
    required String model,
    required List<Map<String, String>> messages,
    CancelToken? cancelToken,
  }) async {
    final body = <String, dynamic>{
      'model': model,
      'messages': messages,
      'temperature': 0.7,
    };

    final headers = <String, dynamic>{
      'Content-Type': 'application/json',
      if (provider.authHeader != null) 'Authorization': provider.authHeader,
      if (provider.userAgent != null) 'User-Agent': provider.userAgent,
    };

    // Fast skip: if the provider still carries the placeholder key
    // (needsKey == true), don't hit the network — rotate instantly.
    if (provider.needsKey) {
      throw LlmException(
        '$provider.label: нужен бесплатный ключ — пропускаю',
        statusCode: 401,
      );
    }

    final Response<dynamic> response;
    try {
      response = await _dio.post<dynamic>(
        '${provider.baseUrl}/${provider.chatPath}',
        data: body,
        options: Options(
          responseType: ResponseType.json,
          validateStatus: (s) => s == null || s < 500,
          headers: headers,
        ),
        cancelToken: cancelToken,
      );
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) rethrow;
      throw LlmException(
        _friendlyError(provider.label, e.response?.statusCode, e.message),
        statusCode: e.response?.statusCode,
      );
    } catch (e) {
      if (e is DioException && e.type == DioExceptionType.cancel) rethrow;
      throw LlmException('Нет сети: $e');
    }

    if (response.statusCode != 200) {
      // Horde budget check: if the response body mentions "budget",
      // treat as rotatable (move to next provider).
      if (response.statusCode == 429) {
        throw LlmException('$provider.label: лимит исчерпан.', statusCode: 429);
      }
      throw LlmException(
        _friendlyError(provider.label, response.statusCode, null),
        statusCode: response.statusCode,
      );
    }

    final data = response.data;
    if (data is Map<String, dynamic>) {
      final choices = data['choices'];
      if (choices is List && choices.isNotEmpty) {
        final msg = choices.first;
        if (msg is Map) {
          final m = msg['message'];
          if (m is Map && m['content'] is String) {
            final content = m['content'] as String;
            // Pollinations returns 200 with "reached its budget" text
            // when its free tier is exhausted — treat as rotatable.
            final lower = content.toLowerCase();
            if (lower.contains('reached its budget') ||
                lower.contains('error code: 1010') ||
                lower.contains('rate limit') ||
                lower.contains('budget exceeded')) {
              throw LlmException(
                '$provider.label: бюджет исчерпан — ротирую',
                statusCode: 429,
              );
            }
            return content;
          }
          if (msg['message'] is String) {
            return msg['message'] as String;
          }
        }
      }
    }
    throw const LlmException('Пустой ответ');
  }

  static String _friendlyError(String label, int? code, String? msg) {
    switch (code) {
      case 401:
        return '$label: 401 нужен ключ';
      case 403:
        return '$label: 403 нет доступа';
      case 404:
        return '$label: 404 модель не найдена';
      case 406:
        return '$label: 406 валидация';
      case 429:
        return '$label: лимит — подожди минуту.';
      case 500:
      case 502:
      case 503:
        return '$label: временно недоступен — повтори через минуту.';
      default:
        return msg?.isEmpty == true
            ? 'Не удалось получить ответ $label.'
            : '$label: ${msg ?? code.toString()}';
    }
  }
}
