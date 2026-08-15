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

  // ── аукцион (ТЗ §2.9) ──────────────────────────────────────────────────────

  /// POST /jobs/{id}/bids — поставить или снизить ставку.
  Future<BidRow> placeBid(
    String token,
    String jobId, {
    required int price,
    String comment = '',
    String? unitId,
    required String idempotencyKey,
  }) async {
    final resp = await _http.post(
      _u('/jobs/$jobId/bids'),
      headers: _headers(token, idempotencyKey: idempotencyKey, json: true),
      body: jsonEncode({
        'price': price,
        'comment': comment,
        if (unitId != null) 'unitId': unitId,
      }),
    );
    return BidRow.fromJson(_handle(resp));
  }

  /// GET /jobs/{id}/bids — лента торга (анонимная).
  Future<List<BidRow>> jobBids(String jobId, {String? token}) async {
    final resp = await _http.get(_u('/jobs/$jobId/bids'), headers: _headers(token));
    return (_handle(resp)['items'] as List? ?? const [])
        .map((e) => BidRow.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  /// GET /jobs/{id}/bids/my — своя ставка; null, если её нет.
  Future<BidRow?> myBidForJob(String token, String jobId) async {
    final resp = await _http.get(_u('/jobs/$jobId/bids/my'), headers: _headers(token));
    final bid = _handle(resp)['bid'];
    if (bid == null) return null;
    return BidRow.fromJson((bid as Map).cast<String, dynamic>());
  }

  /// POST /bids/{id}/withdraw — снять свою ставку.
  Future<BidRow> withdrawBid(String token, String bidId,
      {required String idempotencyKey}) async {
    final resp = await _http.post(
      _u('/bids/$bidId/withdraw'),
      headers: _headers(token, idempotencyKey: idempotencyKey),
    );
    return BidRow.fromJson(_handle(resp));
  }

  /// POST /bids/{id}/accept — заказчик выбирает победителя аукциона.
  Future<BidRow> acceptBid(String token, String bidId,
      {required String idempotencyKey}) async {
    final resp = await _http.post(
      _u('/bids/$bidId/accept'),
      headers: _headers(token, idempotencyKey: idempotencyKey),
    );
    return BidRow.fromJson(_handle(resp));
  }

  /// POST /jobs/{id}/bids/decline-all — отказаться от всех ставок.
  Future<Job> declineAllBids(String token, String jobId,
      {required String idempotencyKey}) async {
    final resp = await _http.post(
      _u('/jobs/$jobId/bids/decline-all'),
      headers: _headers(token, idempotencyKey: idempotencyKey),
    );
    return Job.fromJson(_handle(resp));
  }

  /// GET /chats/{id}/realtime-token — билет на подписку к переписке: канал
  /// закрыт, и выдать билет может только сервис, знающий участников.
  Future<String> chatRealtimeToken(String token, String chatId) async {
    final resp = await _http.get(
      _u('/chats/$chatId/realtime-token'),
      headers: _headers(token),
    );
    return _handle(resp)['token'] as String? ?? '';
  }

  /// GET /realtime/token — билет на подключение к живым обновлениям (ADR-6).
  Future<String> realtimeToken(String token) async {
    final resp = await _http.get(_u('/realtime/token'), headers: _headers(token));
    return _handle(resp)['token'] as String? ?? '';
  }

  /// GET /crm/business — сводка «Мой бизнес» (ТЗ §3.1).
  Future<Business> business(String token, {String period = 'month'}) async {
    final resp = await _http.get(
      _u('/crm/business', {'period': period}),
      headers: _headers(token),
    );
    return Business.fromJson(_handle(resp));
  }

  /// GET /crm/spending — сводка «Мои расходы» заказчика (ТЗ §3.2).
  Future<Spending> spending(String token, {String period = 'month'}) async {
    final resp = await _http.get(
      _u('/crm/spending', {'period': period}),
      headers: _headers(token),
    );
    return Spending.fromJson(_handle(resp));
  }

  // ── модерация техники (ТЗ §4.1) ────────────────────────────────────────────

  /// GET /moderation/equipment — очередь проверки, старые сверху.
  Future<List<ModerationItem>> moderationQueue(String token) async {
    final resp = await _http.get(_u('/moderation/equipment'), headers: _headers(token));
    return (_handle(resp)['items'] as List? ?? const [])
        .map((e) => ModerationItem.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  /// POST /moderation/equipment/{id}/approve — выдать бейдж «Проверен».
  Future<void> approveEquipment(String token, String id,
      {required String idempotencyKey}) async {
    final resp = await _http.post(
      _u('/moderation/equipment/$id/approve'),
      headers: _headers(token, idempotencyKey: idempotencyKey),
    );
    _handle(resp);
  }

  /// POST /moderation/equipment/{id}/reject — отказ с обязательной причиной.
  Future<void> rejectEquipment(String token, String id, String reason,
      {required String idempotencyKey}) async {
    final resp = await _http.post(
      _u('/moderation/equipment/$id/reject'),
      headers: _headers(token, idempotencyKey: idempotencyKey, json: true),
      body: jsonEncode({'reason': reason}),
    );
    _handle(resp);
  }

  // ── публичная карточка человека (ТЗ §2.3) ──────────────────────────────────

  /// GET /users/{id} — имя, город, отметка проверки. Работает без входа:
  /// ссылкой на исполнителя делятся в мессенджере.
  Future<PublicProfile> publicProfile(String userId, {String? token}) async {
    final resp = await _http.get(
      _u('/users/$userId'),
      headers: token == null || token.isEmpty ? const {} : _headers(token),
    );
    return PublicProfile.fromJson(_handle(resp));
  }

  /// GET /equipment/users/{id} — техника человека, которую он показывает миру.
  Future<List<Equipment>> publicEquipment(String userId, {String? token}) async {
    final resp = await _http.get(
      _u('/equipment/users/$userId'),
      headers: token == null || token.isEmpty ? const {} : _headers(token),
    );
    return (_handle(resp)['items'] as List? ?? const [])
        .map((e) => Equipment.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  // ── загрузка файлов (ТЗ §2.5, ADR-5) ───────────────────────────────────────

  /// POST /media/uploads — временные ссылки на загрузку.
  Future<List<UploadLink>> uploadLinks(
    String token, {
    required String contentType,
    required String folder,
    int count = 1,
  }) async {
    final resp = await _http.post(
      _u('/media/uploads'),
      headers: _headers(token, json: true),
      body: jsonEncode({'contentType': contentType, 'folder': folder, 'count': count}),
    );
    return (_handle(resp)['items'] as List? ?? const [])
        .map((e) => UploadLink.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  /// Загрузка байтов по временной ссылке — напрямую в хранилище.
  Future<void> uploadBytes(String uploadUrl, List<int> bytes, String contentType) async {
    final resp = await _http.put(
      Uri.parse(uploadUrl),
      headers: {'Content-Type': contentType},
      body: bytes,
    );
    if (resp.statusCode >= 300) {
      throw ApiException(resp.statusCode, 'Файл не загрузился');
    }
  }

  // ── техника исполнителя (ТЗ §2.5) ──────────────────────────────────────────

  /// GET /equipment/my — список «Моя техника».
  Future<List<Equipment>> myEquipment(String token) async {
    final resp = await _http.get(_u('/equipment/my'), headers: _headers(token));
    return (_handle(resp)['items'] as List? ?? const [])
        .map((e) => Equipment.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  /// POST /equipment/drafts — начать визард.
  Future<Equipment> createEquipmentDraft(String token,
      {String? categoryId, required String idempotencyKey}) async {
    final resp = await _http.post(
      _u('/equipment/drafts'),
      headers: _headers(token, idempotencyKey: idempotencyKey, json: true),
      body: jsonEncode({if (categoryId != null) 'categoryId': categoryId}),
    );
    return Equipment.fromJson(_handle(resp));
  }

  /// PATCH /equipment/{id} — шаг визарда: уходят только заполненные поля.
  Future<Equipment> patchEquipment(
    String token,
    String id, {
    String? categoryId,
    String? brand,
    String? model,
    int? year,
    Map<String, dynamic>? specs,
    int? priceHour,
    int? priceShift,
    int? priceDay,
    int? minHours,
    int? delivery,
    int? crewSize,
    int? crewPrice,
    List<String>? photos,
    List<String>? docs,
    int? draftStep,
    required String idempotencyKey,
  }) async {
    final resp = await _http.patch(
      _u('/equipment/$id'),
      headers: _headers(token, idempotencyKey: idempotencyKey, json: true),
      body: jsonEncode({
        if (categoryId != null) 'categoryId': categoryId,
        if (brand != null) 'brand': brand,
        if (model != null) 'model': model,
        if (year != null) 'year': year,
        if (specs != null) 'specs': specs,
        if (priceHour != null) 'priceHour': priceHour,
        if (priceShift != null) 'priceShift': priceShift,
        if (priceDay != null) 'priceDay': priceDay,
        if (minHours != null) 'minHours': minHours,
        if (delivery != null) 'delivery': delivery,
        if (crewSize != null) 'crewSize': crewSize,
        if (crewPrice != null) 'crewPrice': crewPrice,
        if (photos != null) 'photos': photos,
        if (docs != null) 'docs': docs,
        if (draftStep != null) 'draftStep': draftStep,
      }),
    );
    return Equipment.fromJson(_handle(resp));
  }

  /// POST /equipment/{id}/submit — опубликовать карточку.
  Future<Equipment> submitEquipment(String token, String id,
      {required String idempotencyKey}) async {
    final resp = await _http.post(
      _u('/equipment/$id/submit'),
      headers: _headers(token, idempotencyKey: idempotencyKey),
    );
    return Equipment.fromJson(_handle(resp));
  }

  /// POST /equipment/{id}/archive — снять технику с площадки.
  Future<Equipment> archiveEquipment(String token, String id,
      {required String idempotencyKey}) async {
    final resp = await _http.post(
      _u('/equipment/$id/archive'),
      headers: _headers(token, idempotencyKey: idempotencyKey),
    );
    return Equipment.fromJson(_handle(resp));
  }

  // ── оценки и отзывы (ТЗ §2.13) ─────────────────────────────────────────────

  /// GET /deals/{id}/review — что показать на экране оценки.
  Future<ReviewForm> reviewForm(String token, String dealId) async {
    final resp = await _http.get(_u('/deals/$dealId/review'), headers: _headers(token));
    return ReviewForm.fromJson(_handle(resp));
  }

  /// POST /deals/{id}/review — оставить оценку.
  Future<ReviewResult> leaveReview(
    String token,
    String dealId, {
    required int stars,
    List<String> tags = const [],
    String text = '',
    String issue = '',
    required String idempotencyKey,
  }) async {
    final resp = await _http.post(
      _u('/deals/$dealId/review'),
      headers: _headers(token, idempotencyKey: idempotencyKey, json: true),
      body: jsonEncode({
        'stars': stars,
        'tags': tags,
        'text': text,
        if (issue.isNotEmpty) 'issue': issue,
      }),
    );
    final json = _handle(resp);
    return ReviewResult(
      review: Review.fromJson((json['review'] as Map).cast<String, dynamic>()),
      published: json['published'] as bool? ?? false,
      asksWhatWentWrong: json['asksWhatWentWrong'] as bool? ?? false,
    );
  }

  /// GET /reviews/users/{id} — отзывы о человеке и его рейтинг.
  Future<ReviewsPage> userReviews(String token, String userId,
      {int limit = 20, int offset = 0}) async {
    final resp = await _http.get(
      _u('/reviews/users/$userId', {'limit': '$limit', 'offset': '$offset'}),
      headers: _headers(token),
    );
    return ReviewsPage.fromJson(_handle(resp));
  }

  /// POST /reviews/{id}/reply — публичный ответ на отзыв о себе, один раз.
  Future<Review> replyToReview(String token, String reviewId, String text,
      {required String idempotencyKey}) async {
    final resp = await _http.post(
      _u('/reviews/$reviewId/reply'),
      headers: _headers(token, idempotencyKey: idempotencyKey, json: true),
      body: jsonEncode({'text': text}),
    );
    return Review.fromJson(_handle(resp));
  }

  // ── чаты (ТЗ §2.12) ────────────────────────────────────────────────────────

  /// POST /jobs/{id}/chat — открыть переписку по заданию.
  /// Заказчик указывает исполнителя, исполнитель — нет.
  Future<ChatRow> openChat(String token, String jobId,
      {String? ownerId, required String idempotencyKey}) async {
    final resp = await _http.post(
      _u('/jobs/$jobId/chat'),
      headers: _headers(token, idempotencyKey: idempotencyKey, json: true),
      body: jsonEncode({if (ownerId != null) 'ownerId': ownerId}),
    );
    return ChatRow.fromJson(_handle(resp));
  }

  /// GET /chats — список моих переписок.
  Future<List<ChatRow>> chats(String token, {int limit = 20, int offset = 0}) async {
    final resp = await _http.get(
      _u('/chats', {'limit': '$limit', 'offset': '$offset'}),
      headers: _headers(token),
    );
    return (_handle(resp)['items'] as List? ?? const [])
        .map((e) => ChatRow.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  /// GET /chats/{id} — карточка переписки.
  Future<ChatRow> chat(String token, String chatId) async {
    final resp = await _http.get(_u('/chats/$chatId'), headers: _headers(token));
    return ChatRow.fromJson(_handle(resp));
  }

  /// GET /chats/{id}/messages — история; открытие считается прочтением.
  Future<List<ChatMessage>> messages(String token, String chatId,
      {int limit = 50, int offset = 0}) async {
    final resp = await _http.get(
      _u('/chats/$chatId/messages', {'limit': '$limit', 'offset': '$offset'}),
      headers: _headers(token),
    );
    return (_handle(resp)['items'] as List? ?? const [])
        .map((e) => ChatMessage.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  /// POST /chats/{id}/messages — отправить сообщение.
  Future<SentMessage> sendMessage(String token, String chatId, String text,
      {required String idempotencyKey}) async {
    final resp = await _http.post(
      _u('/chats/$chatId/messages'),
      headers: _headers(token, idempotencyKey: idempotencyKey, json: true),
      body: jsonEncode({'text': text}),
    );
    final json = _handle(resp);
    return SentMessage(
      message: ChatMessage.fromJson((json['message'] as Map).cast<String, dynamic>()),
      contactsMasked: json['contactsMasked'] as bool? ?? false,
    );
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
