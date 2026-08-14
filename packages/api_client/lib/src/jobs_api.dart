import 'dart:convert';

import 'package:http/http.dart' as http;

import 'json_body.dart';
import 'jobs_models.dart';
import 'models.dart';

/// Клиент разделов catalog и orders контракта: справочник категорий и задания.
///
/// Токен передаётся отдельным аргументом, а не хранится внутри: сессия живёт в
/// приложении и может обновиться между вызовами.
class JobsApi {
  JobsApi(this.baseUrl, {http.Client? client}) : _http = client ?? http.Client();

  final String baseUrl;
  final http.Client _http;

  Uri _u(String path, [Map<String, String>? query]) {
    final uri = Uri.parse('$baseUrl$path');
    if (query == null || query.isEmpty) return uri;
    return uri.replace(queryParameters: {...uri.queryParameters, ...query});
  }

  Map<String, String> _headers(String? token, {String? idempotencyKey, bool json = false}) => {
        if (json) 'Content-Type': 'application/json',
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
        if (idempotencyKey != null) 'Idempotency-Key': idempotencyKey,
      };

  Map<String, dynamic> _handle(http.Response resp) {
    final json = decodeJsonBody(resp);
    if (resp.statusCode >= 300) {
      // 422 — разбор по полям для визарда: экран показывает, что именно
      // осталось незаполненным, вместо общего «ошибка сервера».
      if (resp.statusCode == 422 && json['fields'] is Map) {
        throw ValidationException(
          (json['fields'] as Map).map((k, v) => MapEntry(k.toString(), v.toString())),
          json['title'] as String? ?? 'Не хватает данных для публикации',
        );
      }
      throw ApiException(
        resp.statusCode,
        json['detail'] as String? ?? json['title'] as String? ?? 'Ошибка запроса',
      );
    }
    return json;
  }

  List<Job> _jobs(Map<String, dynamic> json) =>
      (json['items'] as List? ?? const [])
          .map((e) => Job.fromJson((e as Map).cast<String, dynamic>()))
          .toList();

  // ── catalog ────────────────────────────────────────────────────────────────

  /// GET /categories — дерево категорий. kind: work | unit.
  Future<List<Category>> categories({String? kind, bool flat = false}) async {
    final resp = await _http.get(_u('/categories', {
      if (kind != null) 'kind': kind,
      if (flat) 'flat': '1',
    }));
    final json = _handle(resp);
    return (json['items'] as List? ?? const [])
        .map((e) => Category.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  // ── orders ─────────────────────────────────────────────────────────────────

  /// GET /jobs — лента. Без токена работает как гостевая (ТЗ §2.1).
  Future<List<Job>> feed({
    String? token,
    double? lat,
    double? lng,
    double? radiusKm,
    List<String> categoryIds = const [],
    String? mode,
    String? query,
    String sort = 'new',
    int limit = 20,
    int offset = 0,
  }) async {
    final resp = await _http.get(
      _u('/jobs', {
        if (lat != null) 'lat': '$lat',
        if (lng != null) 'lng': '$lng',
        if (radiusKm != null) 'radiusKm': '$radiusKm',
        if (categoryIds.isNotEmpty) 'categoryIds': categoryIds.join(','),
        if (mode != null && mode.isNotEmpty) 'mode': mode,
        if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
        'sort': sort,
        'limit': '$limit',
        'offset': '$offset',
      }),
      headers: _headers(token),
    );
    return _jobs(_handle(resp));
  }

  /// GET /jobs/my — мои задания и черновики (главная заказчика).
  Future<List<Job>> myJobs(String token, {int limit = 20, int offset = 0}) async {
    final resp = await _http.get(
      _u('/jobs/my', {'limit': '$limit', 'offset': '$offset'}),
      headers: _headers(token),
    );
    return _jobs(_handle(resp));
  }

  /// GET /jobs/{id} — деталка.
  Future<Job> byId(String id, {String? token}) async {
    final resp = await _http.get(_u('/jobs/$id'), headers: _headers(token));
    return Job.fromJson(_handle(resp));
  }

  /// POST /jobs/drafts — создать черновик (шаг 1 визарда).
  Future<Job> createDraft(String token, JobDraftInput input,
      {required String idempotencyKey}) async {
    final resp = await _http.post(
      _u('/jobs/drafts'),
      headers: _headers(token, idempotencyKey: idempotencyKey, json: true),
      body: jsonEncode(input.toJson()),
    );
    return Job.fromJson(_handle(resp));
  }

  /// PATCH /jobs/drafts/{id} — сохранить шаг визарда.
  ///
  /// Ключ идемпотентности обязателен для всех изменяющих запросов: шлюз без
  /// него отвечает отказом (§2.3.12), да и повтор при обрыве связи не должен
  /// применяться дважды.
  Future<Job> updateDraft(String token, String id, JobDraftInput input,
      {required String idempotencyKey}) async {
    final resp = await _http.patch(
      _u('/jobs/drafts/$id'),
      headers: _headers(token, idempotencyKey: idempotencyKey, json: true),
      body: jsonEncode(input.toJson()),
    );
    return Job.fromJson(_handle(resp));
  }

  /// POST /jobs/{id}/publish — опубликовать. Бросает [ValidationException],
  /// если сервер нашёл незаполненные поля.
  Future<Job> publish(String token, String id, {required String idempotencyKey}) async {
    final resp = await _http.post(
      _u('/jobs/$id/publish'),
      headers: _headers(token, idempotencyKey: idempotencyKey),
    );
    return Job.fromJson(_handle(resp));
  }

  /// POST /jobs/{id}/cancel — снять задание.
  Future<Job> cancel(String token, String id, {required String idempotencyKey}) async {
    final resp = await _http.post(
      _u('/jobs/$id/cancel'),
      headers: _headers(token, idempotencyKey: idempotencyKey),
    );
    return Job.fromJson(_handle(resp));
  }
}
