import 'dart:convert';
import 'package:http/http.dart' as http;
import 'models.dart';

/// Клиент раздела notifications контракта: регистрация и снятие push-токена
/// устройства. Идёт через gateway (Bearer + Idempotency-Key на регистрации).
class DevicesApi {
  DevicesApi(this.baseUrl, {http.Client? client}) : _http = client ?? http.Client();

  final String baseUrl;
  final http.Client _http;

  Uri _u(String path) => Uri.parse('$baseUrl$path');

  /// POST /devices — зарегистрировать/обновить push-токен (идемпотентно по токену).
  Future<void> register({
    required String accessToken,
    required String token,
    required String platform, // android|ios|web
    required String locale, // hy|ru|en
    String? appVersion,
    required String idempotencyKey,
  }) async {
    final resp = await _http.post(
      _u('/devices'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $accessToken',
        'Idempotency-Key': idempotencyKey,
      },
      body: jsonEncode({
        'token': token,
        'platform': platform,
        'locale': locale,
        if (appVersion != null) 'appVersion': appVersion,
      }),
    );
    _ensureOk(resp);
  }

  /// DELETE /devices/{token} — снять регистрацию (logout / отзыв разрешения).
  Future<void> unregister({required String accessToken, required String token}) async {
    final resp = await _http.delete(
      _u('/devices/${Uri.encodeComponent(token)}'),
      headers: {'Authorization': 'Bearer $accessToken'},
    );
    _ensureOk(resp);
  }

  void _ensureOk(http.Response resp) {
    if (resp.statusCode >= 300) {
      final detail = resp.body.isEmpty
          ? 'Ошибка запроса'
          : ((jsonDecode(resp.body) as Map)['detail'] as String? ?? 'Ошибка запроса');
      throw ApiException(resp.statusCode, detail);
    }
  }

  void close() => _http.close();
}
