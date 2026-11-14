// VpnApiClient - talks to a VPN provider REST API using an API key.
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kDebugMode;

import 'vpn_settings.dart';

/// A single VPN server / location offered by the provider.
class ApiVpnServer {
  final String id;
  final String name;
  final String? country;
  final String? countryCode;
  final String? flag;
  final int? pingMs;
  final double? loadPercent;

  const ApiVpnServer({
    required this.id,
    required this.name,
    this.country,
    this.countryCode,
    this.flag,
    this.pingMs,
    this.loadPercent,
  });

  factory ApiVpnServer.fromJson(Map<String, dynamic> json) {
    final id = json['id']?.toString() ?? json['name']?.toString() ?? '';
    final name =
        json['name']?.toString() ?? json['country']?.toString() ?? 'Server';
    final rawPing =
        json['ping'] ?? json['ping_ms'] ?? json['pingMs'] ?? json['latency'];
    final rawLoad = json['load'] ?? json['load_percent'] ?? json['loadPercent'];
    return ApiVpnServer(
      id: id,
      name: name,
      country: json['country']?.toString(),
      countryCode:
          json['country_code']?.toString() ?? json['countryCode']?.toString(),
      flag: json['flag']?.toString(),
      pingMs: rawPing is num
          ? rawPing.round()
          : int.tryParse(rawPing?.toString() ?? ''),
      loadPercent: rawLoad is num
          ? rawLoad.toDouble()
          : double.tryParse(rawLoad?.toString() ?? ''),
    );
  }
}

/// Result of asking the provider to establish a tunnel.
class ApiConnectResult {
  final String? ipAddress;
  final String? protocol;
  final String? config;
  final String? message;

  const ApiConnectResult({
    this.ipAddress,
    this.protocol,
    this.config,
    this.message,
  });

  factory ApiConnectResult.fromJson(Map<String, dynamic> json) =>
      ApiConnectResult(
        ipAddress:
            json['ip']?.toString() ??
            json['ip_address']?.toString() ??
            json['assigned_ip']?.toString(),
        protocol: json['protocol']?.toString(),
        config: json['config']?.toString() ?? json['wg']?.toString(),
        message: json['message']?.toString(),
      );
}

class VpnApiException implements Exception {
  final String message;
  final int? statusCode;
  const VpnApiException(this.message, {this.statusCode});
  @override
  String toString() => message;
}

class VpnApiClient {
  VpnApiClient({required this.settings, Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 20),
            ),
          ) {
    // Never log request headers: they carry `Authorization: Bearer <api key>`.
    // And only ever log at all in debug builds.
    if (kDebugMode) {
      _dio.interceptors.add(
        LogInterceptor(
          requestHeader: false,
          requestBody: false,
          responseBody: false,
        ),
      );
    }
  }

  VpnSettings settings;
  final Dio _dio;

  Options get _authOptions {
    final headers = <String, dynamic>{'Accept': 'application/json'};
    if (settings.apiKey.trim().isNotEmpty) {
      headers['Authorization'] = 'Bearer ${settings.apiKey.trim()}';
    }
    return Options(headers: headers);
  }

  /// Fetch the list of servers from common REST endpoints.
  Future<List<ApiVpnServer>> fetchServers() async {
    final endpoints = _possibleEndpoints;
    Object? lastError = const VpnApiException('Нет API ключа');
    for (final ep in endpoints) {
      try {
        final res = await _dio.get<dynamic>(
          settings.baseUrl + ep,
          options: _authOptions,
        );
        return _parseServerList(res.data);
      } on DioException catch (e) {
        lastError = e;
        final code = e.response?.statusCode;
        if (code == 401 || code == 403) {
          throw VpnApiException(_friendlyAuthError(code!), statusCode: code);
        }
        continue;
      } catch (e) {
        lastError = e;
        continue;
      }
    }
    if (lastError is VpnApiException) throw lastError;
    throw VpnApiException('Не удалось получить список серверов: $lastError');
  }

  List<String> get _possibleEndpoints => [
    '/subscription',
    '/subscribe',
    '/servers',
    '/locations',
    '/v1/servers',
    '/api/servers',
    '/api/v1/servers',
  ];

  List<ApiVpnServer> _parseServerList(dynamic data) {
    final servers = <ApiVpnServer>[];
    if (data is List) {
      for (final item in data) {
        if (item is Map) {
          servers.add(ApiVpnServer.fromJson(Map<String, dynamic>.from(item)));
        }
      }
      return servers;
    }
    if (data is Map) {
      final body = Map<String, dynamic>.from(data);
      final candidates = <dynamic>[
        body['servers'],
        body['data'],
        body['locations'],
        body['results'],
        body['items'],
      ];
      for (final c in candidates) {
        if (c is List) {
          for (final item in c) {
            if (item is Map) {
              servers.add(
                ApiVpnServer.fromJson(Map<String, dynamic>.from(item)),
              );
            }
          }
          if (servers.isNotEmpty) return servers;
        }
      }
      if (body.containsKey('id') || body.containsKey('name')) {
        servers.add(ApiVpnServer.fromJson(body));
      }
    }
    return servers;
  }

  /// Ask the provider to connect to a given server id.
  Future<ApiConnectResult> connect(String serverId) async {
    final endpoints = [
      '/connect',
      '/v1/connect',
      '/api/connect',
      '/api/v1/connect',
      '/servers/$serverId/connect',
    ];
    Object? lastError = const VpnApiException('Нет API ключа');
    for (final ep in endpoints) {
      try {
        final res = await _dio.post<dynamic>(
          settings.baseUrl + ep,
          options: _authOptions,
          data: {
            'server_id': serverId,
            'serverId': serverId,
            'server': serverId,
          },
        );
        final data = res.data;
        if (data is Map) {
          return ApiConnectResult.fromJson(Map<String, dynamic>.from(data));
        }
        return const ApiConnectResult();
      } on DioException catch (e) {
        lastError = e;
        final code = e.response?.statusCode;
        if (code == 401 || code == 403) {
          throw VpnApiException(_friendlyAuthError(code!), statusCode: code);
        }
        continue;
      } catch (e) {
        lastError = e;
        continue;
      }
    }
    if (lastError is VpnApiException) throw lastError;
    throw VpnApiException('Не удалось подключиться: $lastError');
  }

  /// Tell the provider to disconnect.
  Future<void> disconnect({String? serverId}) async {
    final endpoints = [
      '/disconnect',
      '/v1/disconnect',
      '/api/disconnect',
      '/api/v1/disconnect',
    ];
    for (final ep in endpoints) {
      try {
        await _dio.post<dynamic>(
          settings.baseUrl + ep,
          options: _authOptions,
          data: serverId == null
              ? null
              : {'server_id': serverId, 'serverId': serverId},
        );
        return;
      } on DioException catch (e) {
        final code = e.response?.statusCode;
        if (code == 401 || code == 403) {
          throw VpnApiException(_friendlyAuthError(code!), statusCode: code);
        }
        continue;
      } catch (_) {
        continue;
      }
    }
  }

  String _friendlyAuthError(int code) {
    if (code == 401) return 'API ключ неверный (401). Проверь ключ.';
    if (code == 403) {
      return 'API ключ не имеет доступа (403). Проверь права и тариф.';
    }
    return 'Ошибка авторизации ($code).';
  }
}
