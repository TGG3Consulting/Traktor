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

  // ── отклики (ТЗ §2.10) ─────────────────────────────────────────────────────

  List<Offer> _offers(Map<String, dynamic> json) =>
      (json['items'] as List? ?? const [])
          .map((e) => Offer.fromJson((e as Map).cast<String, dynamic>()))
          .toList();

  /// POST /jobs/{id}/offers — откликнуться (accept — согласен на цену,
  /// counter — предлагаю свою).
  Future<Offer> makeOffer(
    String token,
    String jobId, {
    required String kind,
    required int price,
    String comment = '',
    String eta = '',
    String? unitId,
    required String idempotencyKey,
  }) async {
    final resp = await _http.post(
      _u('/jobs/$jobId/offers'),
      headers: _headers(token, idempotencyKey: idempotencyKey, json: true),
      body: jsonEncode({
        'kind': kind,
        'price': price,
        'comment': comment,
        'eta': eta,
        if (unitId != null) 'unitId': unitId,
      }),
    );
    return Offer.fromJson(_handle(resp));
  }

  /// GET /jobs/{id}/offers — отклики по заданию (только для заказчика).
  Future<List<Offer>> jobOffers(String token, String jobId) async {
    final resp = await _http.get(_u('/jobs/$jobId/offers'), headers: _headers(token));
    return _offers(_handle(resp));
  }

  /// GET /jobs/{id}/offers/my — свой отклик; null, если ещё не откликался.
  Future<Offer?> myOfferForJob(String token, String jobId) async {
    final resp = await _http.get(_u('/jobs/$jobId/offers/my'), headers: _headers(token));
    final json = _handle(resp);
    final offer = json['offer'];
    if (offer == null) return null;
    return Offer.fromJson((offer as Map).cast<String, dynamic>());
  }

  /// GET /offers/my — все мои предложения (панель исполнителя).
  Future<List<Offer>> myOffers(String token, {int limit = 20, int offset = 0}) async {
    final resp = await _http.get(
      _u('/offers/my', {'limit': '$limit', 'offset': '$offset'}),
      headers: _headers(token),
    );
    return _offers(_handle(resp));
  }

  /// POST /offers/{id}/withdraw — снять своё предложение.
  Future<Offer> withdrawOffer(String token, String offerId,
      {required String idempotencyKey}) async {
    final resp = await _http.post(
      _u('/offers/$offerId/withdraw'),
      headers: _headers(token, idempotencyKey: idempotencyKey),
    );
    return Offer.fromJson(_handle(resp));
  }

  /// POST /offers/{id}/accept — выбрать исполнителя.
  Future<Offer> acceptOffer(String token, String offerId,
      {required String idempotencyKey}) async {
    final resp = await _http.post(
      _u('/offers/$offerId/accept'),
      headers: _headers(token, idempotencyKey: idempotencyKey),
    );
    return Offer.fromJson(_handle(resp));
  }

  /// POST /offers/{id}/decline — отклонить предложение.
  Future<Offer> declineOffer(String token, String offerId,
      {String reason = '', required String idempotencyKey}) async {
    final resp = await _http.post(
      _u('/offers/$offerId/decline'),
      headers: _headers(token, idempotencyKey: idempotencyKey, json: true),
      body: jsonEncode({'reason': reason}),
    );
    return Offer.fromJson(_handle(resp));
  }

  /// POST /offers/{id}/counter — встречная цена заказчика (один раунд).
  Future<Offer> counterOffer(String token, String offerId, int price,
      {required String idempotencyKey}) async {
    final resp = await _http.post(
      _u('/offers/$offerId/counter'),
      headers: _headers(token, idempotencyKey: idempotencyKey, json: true),
      body: jsonEncode({'price': price}),
    );
    return Offer.fromJson(_handle(resp));
  }

  // ── сделки (ТЗ §2.11) ──────────────────────────────────────────────────────

  /// POST /jobs/{id}/deal — подтвердить выбор и открыть сделку.
  Future<Deal> confirmDeal(String token, String jobId,
      {required String idempotencyKey}) async {
    final resp = await _http.post(
      _u('/jobs/$jobId/deal'),
      headers: _headers(token, idempotencyKey: idempotencyKey),
    );
    return Deal.fromJson(_handle(resp));
  }

  /// GET /jobs/{id}/deal — сделка по заданию; null, если её ещё нет.
  Future<Deal?> dealByJob(String token, String jobId) async {
    final resp = await _http.get(_u('/jobs/$jobId/deal'), headers: _headers(token));
    final json = _handle(resp);
    final deal = json['deal'];
    if (deal == null) return null;
    return Deal.fromJson((deal as Map).cast<String, dynamic>());
  }

  /// GET /deals/{id}
  Future<Deal> deal(String token, String dealId) async {
    final resp = await _http.get(_u('/deals/$dealId'), headers: _headers(token));
    return Deal.fromJson(_handle(resp));
  }

  /// GET /deals/my — мои сделки в обеих ролях.
  Future<List<Deal>> myDeals(String token, {int limit = 20, int offset = 0}) async {
    final resp = await _http.get(
      _u('/deals/my', {'limit': '$limit', 'offset': '$offset'}),
      headers: _headers(token),
    );
    return (_handle(resp)['items'] as List? ?? const [])
        .map((e) => Deal.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  /// POST /deals/{id}/step — следующий шаг работы.
  Future<Deal> dealStep(String token, String dealId, String status,
      {String note = '', required String idempotencyKey}) async {
    final resp = await _http.post(
      _u('/deals/$dealId/step'),
      headers: _headers(token, idempotencyKey: idempotencyKey, json: true),
      body: jsonEncode({'status': status, 'note': note}),
    );
    return Deal.fromJson(_handle(resp));
  }

  /// POST /deals/{id}/cancel — отменить сделку с причиной.
  Future<Deal> cancelDeal(String token, String dealId, String reason,
      {required String idempotencyKey}) async {
    final resp = await _http.post(
      _u('/deals/$dealId/cancel'),
      headers: _headers(token, idempotencyKey: idempotencyKey, json: true),
      body: jsonEncode({'reason': reason}),
    );
    return Deal.fromJson(_handle(resp));
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
