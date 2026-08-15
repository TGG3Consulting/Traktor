import 'dart:convert';
import 'package:http/http.dart' as http;

import 'json_body.dart';
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
      final detail = resp.bodyBytes.isEmpty
          ? 'Ошибка запроса'
          : (decodeJsonBody(resp)['detail'] as String? ?? 'Ошибка запроса');
      throw ApiException(resp.statusCode, detail);
    }
  }

  void close() => _http.close();
}

/// Уведомление из центра уведомлений (ТЗ §2.14).
class AppNotification {
  const AppNotification({
    required this.id,
    required this.title,
    this.kind = 'system',
    this.body = '',
    this.data = const {},
    this.read = false,
    this.createdAt,
  });

  final String id;

  /// Тип события из push-матрицы: offer, auction, deal, message, review, job.
  final String kind;
  final String title;
  final String body;

  /// data['route'] — куда вести по нажатию.
  final Map<String, String> data;
  final bool read;
  final DateTime? createdAt;

  String get route => data['route'] ?? '';

  factory AppNotification.fromJson(Map<String, dynamic> j) => AppNotification(
        id: j['id'] as String? ?? '',
        kind: j['kind'] as String? ?? 'system',
        title: j['title'] as String? ?? '',
        body: j['body'] as String? ?? '',
        data: ((j['data'] as Map?) ?? const {})
            .map((k, v) => MapEntry('$k', '$v')),
        read: j['read'] as bool? ?? false,
        createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '')?.toLocal(),
      );
}

/// Лента центра уведомлений вместе со счётчиком непрочитанного.
class NotificationsPage {
  const NotificationsPage({this.items = const [], this.unread = 0});

  final List<AppNotification> items;
  final int unread;

  factory NotificationsPage.fromJson(Map<String, dynamic> j) => NotificationsPage(
        items: ((j['items'] as List?) ?? const [])
            .map((e) => AppNotification.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
        unread: j['unread'] as int? ?? 0,
      );
}

/// Клиент центра уведомлений (ТЗ §2.14).
///
/// Push доходит не всегда, поэтому лента — основной способ ничего не
/// пропустить, а не дубль пуша.
class NotificationsApi {
  NotificationsApi(this.baseUrl, {http.Client? client})
      : _http = client ?? http.Client();

  final String baseUrl;
  final http.Client _http;

  Uri _u(String path, [Map<String, String>? query]) =>
      Uri.parse('$baseUrl$path').replace(queryParameters: query);

  /// GET /notifications — лента событий и счётчик непрочитанного.
  Future<NotificationsPage> feed(String token, {int limit = 30, int offset = 0}) async {
    final resp = await _http.get(
      _u('/notifications', {'limit': '$limit', 'offset': '$offset'}),
      headers: {'Authorization': 'Bearer $token'},
    );
    _ensureOkStatic(resp);
    return NotificationsPage.fromJson(decodeJsonBody(resp));
  }

  /// GET /notifications/settings — что человеку присылать (ТЗ §2.14).
  Future<NotificationPrefs> prefs(String token) async {
    final resp = await _http.get(
      _u('/notifications/settings'),
      headers: {'Authorization': 'Bearer $token'},
    );
    _ensureOkStatic(resp);
    return NotificationPrefs.fromJson(decodeJsonBody(resp));
  }

  /// PUT /notifications/settings — меняем только те поля, что переключили.
  Future<NotificationPrefs> savePrefs(
    String token, {
    bool? auctions,
    bool? deals,
    bool? chat,
    bool? newJobs,
    bool? marketing,
    bool? quietHours,
    int? quietFrom,
    int? quietTo,
    bool? outbidAlways,
  }) async {
    final resp = await _http.put(
      _u('/notifications/settings'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        if (auctions != null) 'auctions': auctions,
        if (deals != null) 'deals': deals,
        if (chat != null) 'chat': chat,
        if (newJobs != null) 'newJobs': newJobs,
        if (marketing != null) 'marketing': marketing,
        if (quietHours != null) 'quietHours': quietHours,
        if (quietFrom != null) 'quietFrom': quietFrom,
        if (quietTo != null) 'quietTo': quietTo,
        if (outbidAlways != null) 'outbidAlways': outbidAlways,
      }),
    );
    _ensureOkStatic(resp);
    return NotificationPrefs.fromJson(decodeJsonBody(resp));
  }

  /// POST /notifications/read — отметить прочитанными. Пустой список — все.
  Future<void> markRead(String token,
      {List<String> ids = const [], required String idempotencyKey}) async {
    final resp = await _http.post(
      _u('/notifications/read'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
        // Шлюз требует ключ на любой мутации (правило 12): повторное нажатие
        // «прочитать все» не должно превращаться во вторую операцию.
        'Idempotency-Key': idempotencyKey,
      },
      body: jsonEncode({'ids': ids}),
    );
    _ensureOkStatic(resp);
  }

  void close() => _http.close();
}

void _ensureOkStatic(http.Response resp) {
  if (resp.statusCode >= 300) {
    final detail = resp.bodyBytes.isEmpty
        ? 'Ошибка запроса'
        : (decodeJsonBody(resp)['detail'] as String? ?? 'Ошибка запроса');
    throw ApiException(resp.statusCode, detail);
  }
}

/// Настройки уведомлений (ТЗ §2.14).
class NotificationPrefs {
  const NotificationPrefs({
    this.auctions = true,
    this.deals = true,
    this.chat = true,
    this.newJobs = true,
    this.marketing = false,
    this.quietHours = true,
    this.quietFrom = 22,
    this.quietTo = 8,
    this.outbidAlways = false,
  });

  final bool auctions;
  final bool deals;
  final bool chat;
  final bool newJobs;

  /// Рассылка — только по согласию.
  final bool marketing;

  final bool quietHours;
  final int quietFrom;
  final int quietTo;

  /// «Вашу ставку перебили» будит и ночью, если человек так решил.
  final bool outbidAlways;

  factory NotificationPrefs.fromJson(Map<String, dynamic> j) => NotificationPrefs(
        auctions: j['auctions'] as bool? ?? true,
        deals: j['deals'] as bool? ?? true,
        chat: j['chat'] as bool? ?? true,
        newJobs: j['newJobs'] as bool? ?? true,
        marketing: j['marketing'] as bool? ?? false,
        quietHours: j['quietHours'] as bool? ?? true,
        quietFrom: j['quietFrom'] as int? ?? 22,
        quietTo: j['quietTo'] as int? ?? 8,
        outbidAlways: j['outbidAlways'] as bool? ?? false,
      );
}
