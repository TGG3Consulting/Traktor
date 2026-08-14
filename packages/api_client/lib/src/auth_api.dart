import 'dart:convert';
import 'package:http/http.dart' as http;
import 'models.dart';

/// Клиент раздела identity контракта. baseUrl — например
/// https://api.traktor.am/v1 (прод) или http://10.0.2.2:8080/v1 (Android-эмулятор
/// к локальному серверу).
class AuthApi {
  AuthApi(this.baseUrl, {http.Client? client}) : _http = client ?? http.Client();

  final String baseUrl;
  final http.Client _http;

  Uri _u(String path) => Uri.parse('$baseUrl$path');

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body,
      {Map<String, String>? headers}) async {
    final resp = await _http.post(
      _u(path),
      headers: {'Content-Type': 'application/json', ...?headers},
      body: jsonEncode(body),
    );
    return _handle(resp);
  }

  Map<String, dynamic> _handle(http.Response resp) {
    final Map<String, dynamic> json =
        resp.body.isEmpty ? {} : (jsonDecode(resp.body) as Map).cast<String, dynamic>();
    if (resp.statusCode >= 300) {
      throw ApiException(resp.statusCode, json['detail'] as String? ?? 'Ошибка запроса');
    }
    return json;
  }

  /// POST /auth/otp/start
  Future<void> otpStart(String phone) async {
    await _post('/auth/otp/start', {'phone': phone});
  }

  /// POST /auth/otp/verify (с Idempotency-Key)
  Future<Session> otpVerify(String phone, String code, {required String idempotencyKey}) async {
    final json = await _post(
      '/auth/otp/verify',
      {'phone': phone, 'code': code},
      headers: {'Idempotency-Key': idempotencyKey},
    );
    return Session.fromJson(json);
  }

  /// POST /auth/refresh
  Future<Session> refresh(String refreshToken) async {
    final json = await _post('/auth/refresh', {'refreshToken': refreshToken});
    return Session.fromJson(json);
  }

  /// GET /me (Bearer)
  Future<ApiUser> getMe(String accessToken) async {
    final resp = await _http.get(_u('/me'), headers: {'Authorization': 'Bearer $accessToken'});
    return ApiUser.fromJson(_handle(resp));
  }

  /// PATCH /me (Bearer + Idempotency-Key) — обновить профиль: имя, город,
  /// активная роль. Передаются только заданные поля. Возвращает свежий профиль.
  Future<ApiUser> updateMe(
    String accessToken, {
    String? name,
    String? city,
    String? activeRole,
    required String idempotencyKey,
  }) async {
    final resp = await _http.patch(
      _u('/me'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $accessToken',
        'Idempotency-Key': idempotencyKey,
      },
      body: jsonEncode({
        if (name != null) 'name': name,
        if (city != null) 'city': city,
        if (activeRole != null) 'activeRole': activeRole,
      }),
    );
    return ApiUser.fromJson(_handle(resp));
  }

  void close() => _http.close();
}
