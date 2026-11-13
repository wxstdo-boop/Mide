// Tests for the pure GitHub-release parsing + the Dio-backed VpnApiClient.
// A stub Dio adapter stands in for the network so the real client code path
// (endpoint fallback, auth header, parsing) runs unchanged.
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mide/features/vpn/vpn_api_client.dart';
import 'package:mide/features/vpn/vpn_settings.dart';

/// A Dio adapter that answers every request from a scripted handler.
class _ScriptedAdapter implements HttpClientAdapter {
  _ScriptedAdapter(this.handler);

  final Future<ResponseBody> Function(RequestOptions options) handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) =>
      handler(options);

  @override
  void close({bool force = false}) {}
}

ResponseBody _jsonBody(String body, {int status = 200}) =>
    ResponseBody.fromString(body, status, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });

void main() {
  VpnApiClient clientWith(
    Future<ResponseBody> Function(RequestOptions) handler, {
    String apiKey = 'k',
    String baseUrl = 'https://api.test',
  }) {
    final dio = Dio(BaseOptions(baseUrl: baseUrl))
      ..httpClientAdapter = _ScriptedAdapter(handler);
    return VpnApiClient(
      settings: VpnSettings(apiKey: apiKey, baseUrl: baseUrl),
      dio: dio,
    );
  }

  group('VpnApiClient.fetchServers', () {
    test('parses a bare list response', () async {
      final client = clientWith((o) async =>
          _jsonBody('[{"id":"a","name":"Alpha"},{"id":"b","name":"Beta"}]'));
      final servers = await client.fetchServers();
      expect(servers.map((s) => s.id), ['a', 'b']);
    });

    test('parses a wrapped {data:[...]} response', () async {
      final client = clientWith(
          (o) async => _jsonBody('{"data":[{"id":"z","name":"Zeta"}]}'));
      final servers = await client.fetchServers();
      expect(servers.single.name, 'Zeta');
    });

    test('sends the API key as a Bearer header', () async {
      String? seen;
      final client = clientWith((o) async {
        seen = o.headers['Authorization']?.toString();
        return _jsonBody('[]');
      }, apiKey: 'secret-key');
      await client.fetchServers();
      expect(seen, 'Bearer secret-key');
    });

    test('maps 401 to a friendly auth error', () async {
      final client = clientWith((o) async => ResponseBody.fromString('', 401));
      expect(
        () => client.fetchServers(),
        throwsA(isA<VpnApiException>()
            .having((e) => e.statusCode, 'statusCode', 401)),
      );
    });

    test('falls back across endpoints before failing', () async {
      final tried = <String>[];
      final client = clientWith((o) async {
        tried.add(o.uri.path);
        if (o.uri.path == '/servers') {
          return _jsonBody('[{"id":"s1","name":"One"}]');
        }
        return ResponseBody.fromString('', 404);
      });
      final servers = await client.fetchServers();
      expect(servers.single.id, 's1');
      expect(tried.first, '/subscription');
      expect(tried, contains('/servers'));
    });
  });

  group('VpnApiClient.connect', () {
    test('returns the parsed connect result', () async {
      final client = clientWith(
          (o) async => _jsonBody('{"ip":"1.2.3.4","protocol":"WireGuard"}'));
      final res = await client.connect('srv-1');
      expect(res.ipAddress, '1.2.3.4');
      expect(res.protocol, 'WireGuard');
    });

    test('surfaces 403 as an auth error', () async {
      final client = clientWith((o) async => ResponseBody.fromString('', 403));
      expect(
        () => client.connect('srv-1'),
        throwsA(isA<VpnApiException>()
            .having((e) => e.statusCode, 'statusCode', 403)),
      );
    });
  });

  group('VpnApiClient.disconnect', () {
    test('completes on a successful disconnect', () async {
      final client = clientWith((o) async => _jsonBody('{}'));
      await client.disconnect(serverId: 'srv-1');
    });

    test('throws a friendly error on 401', () async {
      final client = clientWith((o) async => ResponseBody.fromString('', 401));
      expect(
        () => client.disconnect(),
        throwsA(isA<VpnApiException>()
            .having((e) => e.statusCode, 'statusCode', 401)),
      );
    });
  });
}
