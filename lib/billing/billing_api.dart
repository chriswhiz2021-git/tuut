// Tuut – Verbindung zum Guthaben-Dienst (Port 8787 auf demselben Server wie Matrix).
// Anmeldung mit dem Matrix-Zugangstoken; der Dienst prüft es beim Matrix-Server.
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';

class BillingException implements Exception {
  final String message;
  BillingException(this.message);
  @override
  String toString() => message;
}

class BillingApi {
  final Client client;
  BillingApi(this.client);

  Uri _uri(String path, [Map<String, String>? query]) {
    final hs = client.homeserver;
    if (hs == null) throw BillingException('Nicht angemeldet.');
    return Uri(scheme: hs.scheme, host: hs.host, port: 8787, path: path, queryParameters: query);
  }

  Map<String, String> get _headers => {
        'Authorization': 'Bearer ${client.accessToken ?? ''}',
        'Content-Type': 'application/json',
      };

  Future<Map<String, dynamic>> getJson(String path, [Map<String, String>? query]) =>
      _send(() => http.get(_uri(path, query), headers: _headers));

  Future<Map<String, dynamic>> postJson(String path, [Map<String, dynamic>? body]) =>
      _send(() => http.post(_uri(path), headers: _headers, body: jsonEncode(body ?? <String, dynamic>{})));

  Future<Map<String, dynamic>> _send(Future<http.Response> Function() send) async {
    http.Response r;
    try {
      r = await send().timeout(const Duration(seconds: 30));
    } on BillingException {
      rethrow;
    } catch (_) {
      throw BillingException('Guthaben-Dienst nicht erreichbar. Läuft der Server in Version 3 (SERVER-START)?');
    }
    Map<String, dynamic> data = {};
    try {
      final decoded = jsonDecode(utf8.decode(r.bodyBytes));
      if (decoded is Map<String, dynamic>) data = decoded;
    } catch (_) {}
    if (r.statusCode >= 400) {
      final detail = data['detail'];
      throw BillingException(detail is String ? detail : 'Fehler ${r.statusCode} beim Guthaben-Dienst.');
    }
    return data;
  }
}
