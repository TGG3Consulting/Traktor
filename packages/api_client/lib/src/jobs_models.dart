/// Модели разделов catalog и orders контракта (Category, Job, JobDraft).
///
/// Разбор намеренно мягкий: отсутствующее поле не роняет экран, а даёт
/// разумное значение по умолчанию — приложение должно пережить сервер, который
/// на версию новее.

/// Название на трёх языках проекта: переключение языка не требует запроса.
class LocalizedName {
  const LocalizedName({this.hy = '', this.ru = '', this.en = ''});

  final String hy;
  final String ru;
  final String en;

  factory LocalizedName.fromJson(Map<String, dynamic> j) => LocalizedName(
        hy: j['hy'] as String? ?? '',
        ru: j['ru'] as String? ?? '',
        en: j['en'] as String? ?? '',
      );

  /// Название для кода языка приложения; при пустом переводе — русский.
  String forLang(String lang) {
    switch (lang) {
      case 'hy':
        return hy.isNotEmpty ? hy : ru;
      case 'en':
        return en.isNotEmpty ? en : ru;
      default:
        return ru;
    }
  }
}

/// Поле характеристик из шаблона категории. По нему строится поле формы:
/// [type] выбирает виджет, [unit] — подпись, [min]/[max] — проверку.
class SpecField {
  const SpecField({
    required this.key,
    required this.type,
    this.unit = '',
    this.min,
    this.max,
    this.options = const [],
    this.label = const LocalizedName(),
    this.required = false,
  });

  final String key;
  final String type; // number | text | select | bool
  final String unit;
  final double? min;
  final double? max;
  final List<String> options;
  final LocalizedName label;
  final bool required;

  /// Тело для правки справочника: сервер ждёт подписи плоскими полями.
  Map<String, dynamic> toEditJson() => {
        'key': key,
        'type': type,
        if (unit.isNotEmpty) 'unit': unit,
        if (min != null) 'min': min,
        if (max != null) 'max': max,
        if (options.isNotEmpty) 'options': options,
        if (label.hy.isNotEmpty) 'label_hy': label.hy,
        'label_ru': label.ru,
        if (label.en.isNotEmpty) 'label_en': label.en,
        if (required) 'required': true,
      };

  factory SpecField.fromJson(Map<String, dynamic> j) => SpecField(
        key: j['key'] as String? ?? '',
        type: j['type'] as String? ?? 'text',
        unit: j['unit'] as String? ?? '',
        min: (j['min'] as num?)?.toDouble(),
        max: (j['max'] as num?)?.toDouble(),
        options: (j['options'] as List?)?.map((e) => e.toString()).toList() ?? const [],
        label: LocalizedName(
          hy: j['label_hy'] as String? ?? '',
          ru: j['label_ru'] as String? ?? '',
          en: j['label_en'] as String? ?? '',
        ),
        required: j['required'] as bool? ?? false,
      );
}

/// Узел справочника: вид работ или техника.
class Category {
  const Category({
    required this.id,
    required this.kind,
    required this.slug,
    required this.name,
    this.icon = 'wrench',
    this.specTemplate = const [],
    this.children = const [],
    this.parentId,
    this.sortOrder = 0,
    this.active = true,
  });

  final String id;
  final String? parentId;
  final String kind; // work | unit
  final String slug;
  final LocalizedName name;

  /// Имя иконки Phosphor из design_system (TkIcons). Эмодзи в интерфейсе
  /// запрещены (правило 8), поэтому справочник хранит именно имя иконки.
  final String icon;
  final List<SpecField> specTemplate;
  final List<Category> children;
  final int sortOrder;

  /// Видна ли категория в приложении. Скрытая остаётся в базе: на неё
  /// ссылаются уже созданные задания и техника (ТЗ §4.1, п.5).
  final bool active;

  /// Тело запроса на правку справочника (ТЗ §4.1, п.5).
  Map<String, dynamic> toEditJson() => {
        'parentId': parentId,
        'kind': kind,
        'slug': slug,
        'name': {'hy': name.hy, 'ru': name.ru, 'en': name.en},
        'icon': icon,
        'sortOrder': sortOrder,
        'specTemplate': specTemplate.map((f) => f.toEditJson()).toList(),
      };

  Category copyWith({
    String? id,
    String? parentId,
    bool clearParent = false,
    String? kind,
    String? slug,
    LocalizedName? name,
    String? icon,
    List<SpecField>? specTemplate,
    int? sortOrder,
    bool? active,
  }) =>
      Category(
        id: id ?? this.id,
        parentId: clearParent ? null : (parentId ?? this.parentId),
        kind: kind ?? this.kind,
        slug: slug ?? this.slug,
        name: name ?? this.name,
        icon: icon ?? this.icon,
        specTemplate: specTemplate ?? this.specTemplate,
        children: children,
        sortOrder: sortOrder ?? this.sortOrder,
        active: active ?? this.active,
      );

  factory Category.fromJson(Map<String, dynamic> j) => Category(
        id: j['id'] as String? ?? '',
        parentId: j['parentId'] as String?,
        kind: j['kind'] as String? ?? 'work',
        slug: j['slug'] as String? ?? '',
        name: LocalizedName.fromJson((j['name'] as Map?)?.cast<String, dynamic>() ?? const {}),
        icon: j['icon'] as String? ?? 'wrench',
        specTemplate: (j['specTemplate'] as List?)
                ?.map((e) => SpecField.fromJson((e as Map).cast<String, dynamic>()))
                .toList() ??
            const [],
        children: (j['children'] as List?)
                ?.map((e) => Category.fromJson((e as Map).cast<String, dynamic>()))
                .toList() ??
            const [],
        sortOrder: j['sortOrder'] as int? ?? 0,
        active: j['active'] as bool? ?? true,
      );
}

/// Точка на карте.
class Geo {
  const Geo(this.lat, this.lng);
  final double lat;
  final double lng;

  factory Geo.fromJson(Map<String, dynamic> j) =>
      Geo((j['lat'] as num?)?.toDouble() ?? 0, (j['lng'] as num?)?.toDouble() ?? 0);

  Map<String, dynamic> toJson() => {'lat': lat, 'lng': lng};
}

/// Настройки обратного аукциона. reserveAmount приходит только владельцу.
class AuctionSettings {
  const AuctionSettings({
    this.durationH = 24,
    this.endsAt,
    this.reserveAmount,
    this.autoExtend = true,
    this.decisionWindowH = 12,
  });

  final int durationH;
  final DateTime? endsAt;
  final int? reserveAmount;
  final bool autoExtend;
  final int decisionWindowH;

  factory AuctionSettings.fromJson(Map<String, dynamic> j) => AuctionSettings(
        durationH: j['durationH'] as int? ?? 24,
        endsAt: DateTime.tryParse(j['endsAt'] as String? ?? '')?.toLocal(),
        reserveAmount: (j['reserveAmount'] as num?)?.toInt(),
        autoExtend: j['autoExtend'] as bool? ?? true,
        decisionWindowH: j['decisionWindowH'] as int? ?? 12,
      );

  Map<String, dynamic> toJson() => {
        'durationH': durationH,
        if (reserveAmount != null) 'reserveAmount': reserveAmount,
        'autoExtend': autoExtend,
        'decisionWindowH': decisionWindowH,
      };
}

/// Статусы задания (ТЗ §4.4). Единая цветовая карта — в design_system.
class JobStatus {
  static const draft = 'draft';
  static const published = 'published';
  static const collectingOffers = 'collecting_offers';
  static const bidding = 'bidding';
  static const dealPending = 'deal_pending';
  static const deciding = 'deciding';
  static const confirmed = 'confirmed';
  static const inProgress = 'in_progress';
  static const workDone = 'work_done';
  static const completed = 'completed';
  static const disputed = 'disputed';
  static const cancelled = 'cancelled';
  static const declinedAll = 'declined_all';
  static const expired = 'expired';
  static const expiredNoBids = 'expired_no_bids';
}

/// Задание.
class Job {
  const Job({
    required this.id,
    required this.clientId,
    required this.status,
    this.orderType = 'job',
    this.categoryId,
    this.openToAny = false,
    this.title = '',
    this.description = '',
    this.params = const {},
    this.photos = const [],
    this.geo,
    this.address = '',
    this.access = 'unknown',
    this.dateMode = 'asap',
    this.dateStart,
    this.dateEnd,
    this.budgetAmount,
    this.currency = 'AMD',
    this.mode = 'fixed',
    this.auction,
    this.workersCount = 0,
    this.draftStep = 1,
    this.viewsCount = 0,
    this.offersCount = 0,
    this.distanceM,
    this.publishedAt,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String clientId;
  final String status;
  final String orderType;
  final String? categoryId;
  final bool openToAny;
  final String title;
  final String description;
  final Map<String, dynamic> params;
  final List<String> photos;
  final Geo? geo;
  final String address;
  final String access; // yes | no | unknown
  final String dateMode; // asap | range | exact
  final DateTime? dateStart;
  final DateTime? dateEnd;
  final int? budgetAmount;
  final String currency;
  final String mode; // fixed | auction
  final AuctionSettings? auction;
  final int workersCount;
  final int draftStep;
  final int viewsCount;
  final int offersCount;

  /// Расстояние от точки поиска — приходит только в ленте.
  final double? distanceM;
  final DateTime? publishedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isDraft => status == JobStatus.draft;
  bool get isAuction => mode == 'auction';

  factory Job.fromJson(Map<String, dynamic> j) => Job(
        id: j['id'] as String? ?? '',
        clientId: j['clientId'] as String? ?? '',
        status: j['status'] as String? ?? JobStatus.draft,
        orderType: j['orderType'] as String? ?? 'job',
        categoryId: j['categoryId'] as String?,
        openToAny: j['openToAny'] as bool? ?? false,
        title: j['title'] as String? ?? '',
        description: j['description'] as String? ?? '',
        params: (j['params'] as Map?)?.cast<String, dynamic>() ?? const {},
        photos: (j['photos'] as List?)?.map((e) => e.toString()).toList() ?? const [],
        geo: j['geo'] == null ? null : Geo.fromJson((j['geo'] as Map).cast<String, dynamic>()),
        address: j['address'] as String? ?? '',
        access: j['access'] as String? ?? 'unknown',
        dateMode: j['dateMode'] as String? ?? 'asap',
        dateStart: DateTime.tryParse(j['dateStart'] as String? ?? '')?.toLocal(),
        dateEnd: DateTime.tryParse(j['dateEnd'] as String? ?? '')?.toLocal(),
        budgetAmount: (j['budgetAmount'] as num?)?.toInt(),
        currency: j['currency'] as String? ?? 'AMD',
        mode: j['mode'] as String? ?? 'fixed',
        auction: j['auction'] == null
            ? null
            : AuctionSettings.fromJson((j['auction'] as Map).cast<String, dynamic>()),
        workersCount: j['workersCount'] as int? ?? 0,
        draftStep: j['draftStep'] as int? ?? 1,
        viewsCount: j['viewsCount'] as int? ?? 0,
        offersCount: j['offersCount'] as int? ?? 0,
        distanceM: (j['distanceM'] as num?)?.toDouble(),
        publishedAt: DateTime.tryParse(j['publishedAt'] as String? ?? '')?.toLocal(),
        createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '')?.toLocal(),
        updatedAt: DateTime.tryParse(j['updatedAt'] as String? ?? '')?.toLocal(),
      );
}

/// Поля визарда для отправки на сервер. Незаданное поле не отправляется —
/// сервер не трогает его, поэтому сохранение шага не затирает соседние.
class JobDraftInput {
  const JobDraftInput({
    this.orderType,
    this.categoryId,
    this.openToAny,
    this.title,
    this.description,
    this.params,
    this.photos,
    this.geo,
    this.address,
    this.access,
    this.dateMode,
    this.dateStart,
    this.dateEnd,
    this.budgetAmount,
    this.currency,
    this.mode,
    this.auction,
    this.workersCount,
    this.draftStep,
  });

  final String? orderType;
  final String? categoryId;
  final bool? openToAny;
  final String? title;
  final String? description;
  final Map<String, dynamic>? params;
  final List<String>? photos;
  final Geo? geo;
  final String? address;
  final String? access;
  final String? dateMode;
  final DateTime? dateStart;
  final DateTime? dateEnd;
  final int? budgetAmount;
  final String? currency;
  final String? mode;
  final AuctionSettings? auction;
  final int? workersCount;
  final int? draftStep;

  Map<String, dynamic> toJson() => {
        if (orderType != null) 'orderType': orderType,
        if (categoryId != null) 'categoryId': categoryId,
        if (openToAny != null) 'openToAny': openToAny,
        if (title != null) 'title': title,
        if (description != null) 'description': description,
        if (params != null) 'params': params,
        if (photos != null) 'photos': photos,
        if (geo != null) 'geo': geo!.toJson(),
        if (address != null) 'address': address,
        if (access != null) 'access': access,
        if (dateMode != null) 'dateMode': dateMode,
        if (dateStart != null) 'dateStart': dateStart!.toUtc().toIso8601String(),
        if (dateEnd != null) 'dateEnd': dateEnd!.toUtc().toIso8601String(),
        if (budgetAmount != null) 'budgetAmount': budgetAmount,
        if (currency != null) 'currency': currency,
        if (mode != null) 'mode': mode,
        if (auction != null) 'auction': auction!.toJson(),
        if (workersCount != null) 'workersCount': workersCount,
        if (draftStep != null) 'draftStep': draftStep,
      };
}

/// Ошибка проверки перед публикацией: сервер присылает разбор по полям,
/// экран подсвечивает их и пишет, чего не хватает.
class ValidationException implements Exception {
  ValidationException(this.fields, [this.title = 'Не хватает данных для публикации']);

  final Map<String, String> fields;
  final String title;

  @override
  String toString() => title;
}

/// Отклик исполнителя на задание с фиксированной ценой (ТЗ §2.10).
class Offer {
  const Offer({
    required this.id,
    required this.jobId,
    required this.ownerId,
    required this.kind,
    required this.price,
    required this.status,
    this.currency = 'AMD',
    this.comment = '',
    this.eta = '',
    this.unitId,
    this.declineReason = '',
    this.clientCounterPrice,
    this.clientCounterAt,
    this.createdAt,
    this.updatedAt,
    this.ownerName = 'Исполнитель',
    this.ownerCity = '',
    this.ownerRating = 0,
    this.ownerRatingCount = 0,
    this.ownerVerified = false,
  });

  final String id;
  final String jobId;
  final String ownerId;

  /// accept — согласен на цену задания, counter — предлагает свою.
  final String kind;
  final int price;
  final String currency;
  final String comment;

  /// Когда сможет приступить — свободный текст («завтра с утра»).
  final String eta;
  final String? unitId;

  /// active | withdrawn | declined | accepted | counter_offered
  final String status;
  final String declineReason;

  /// Встречная цена заказчика (один раунд торга).
  final int? clientCounterPrice;
  final DateTime? clientCounterAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Имя и рейтинг исполнителя — приходят из сервиса профилей; пока профиль
  /// не заполнен, показываем обезличенную подпись.
  final String ownerName;
  final String ownerCity;
  final double ownerRating;
  final int ownerRatingCount;
  final bool ownerVerified;

  bool get isActive => status == 'active' || status == 'counter_offered';
  bool get isAccepted => status == 'accepted';
  bool get hasCounter => clientCounterPrice != null;

  factory Offer.fromJson(Map<String, dynamic> j) => Offer(
        id: j['id'] as String? ?? '',
        jobId: j['jobId'] as String? ?? '',
        ownerId: j['ownerId'] as String? ?? '',
        kind: j['kind'] as String? ?? 'accept',
        price: (j['price'] as num?)?.toInt() ?? 0,
        currency: j['currency'] as String? ?? 'AMD',
        comment: j['comment'] as String? ?? '',
        eta: j['eta'] as String? ?? '',
        unitId: j['unitId'] as String?,
        status: j['status'] as String? ?? 'active',
        declineReason: j['declineReason'] as String? ?? '',
        clientCounterPrice: (j['clientCounterPrice'] as num?)?.toInt(),
        clientCounterAt: DateTime.tryParse(j['clientCounterAt'] as String? ?? '')?.toLocal(),
        createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '')?.toLocal(),
        updatedAt: DateTime.tryParse(j['updatedAt'] as String? ?? '')?.toLocal(),
        ownerName: (j['ownerName'] as String?)?.trim().isNotEmpty == true
            ? j['ownerName'] as String
            : 'Исполнитель',
        ownerCity: j['ownerCity'] as String? ?? '',
        ownerRating: (j['ownerRating'] as num?)?.toDouble() ?? 0,
        ownerRatingCount: j['ownerRatingCount'] as int? ?? 0,
        ownerVerified: j['ownerVerified'] as bool? ?? false,
      );
}

/// Событие в истории сделки: кто и когда что сделал.
class DealEvent {
  const DealEvent({required this.status, required this.at, this.byId = '', this.note = ''});

  final String status;
  final DateTime at;
  final String byId;
  final String note;

  factory DealEvent.fromJson(Map<String, dynamic> j) => DealEvent(
        status: j['status'] as String? ?? '',
        at: DateTime.tryParse(j['at'] as String? ?? '')?.toLocal() ?? DateTime.now(),
        byId: j['byId'] as String? ?? '',
        note: j['note'] as String? ?? '',
      );
}

/// Сделка (ТЗ §2.11): то, что происходит после подтверждения выбора.
class Deal {
  const Deal({
    required this.id,
    required this.jobId,
    required this.clientId,
    required this.ownerId,
    required this.price,
    required this.status,
    this.offerId,
    this.currency = 'AMD',
    this.timeline = const [],
    this.acceptanceDeadline,
    this.cancelReason = '',
    this.cancelledBy,
    this.createdAt,
    this.updatedAt,
    this.closedAt,
    this.clientName = 'Заказчик',
    this.ownerName = 'Исполнитель',
    this.ownerRating = 0,
  });

  final String id;
  final String jobId;
  final String? offerId;
  final String clientId;
  final String ownerId;
  final int price;
  final String currency;

  /// confirmed | on_the_way | in_progress | work_done | completed | disputed | cancelled
  final String status;
  final List<DealEvent> timeline;

  /// До какого момента заказчик может принять работу; потом — автоприёмка.
  final DateTime? acceptanceDeadline;
  final String cancelReason;
  final String? cancelledBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? closedAt;

  /// Имена сторон: на экране сделки люди уже договорились и должны видеть,
  /// с кем имеют дело.
  final String clientName;
  final String ownerName;
  final double ownerRating;

  bool get isClosed => status == 'completed' || status == 'cancelled';

  factory Deal.fromJson(Map<String, dynamic> j) => Deal(
        id: j['id'] as String? ?? '',
        jobId: j['jobId'] as String? ?? '',
        offerId: j['offerId'] as String?,
        clientId: j['clientId'] as String? ?? '',
        ownerId: j['ownerId'] as String? ?? '',
        price: (j['price'] as num?)?.toInt() ?? 0,
        currency: j['currency'] as String? ?? 'AMD',
        status: j['status'] as String? ?? 'confirmed',
        timeline: (j['timeline'] as List? ?? const [])
            .map((e) => DealEvent.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
        acceptanceDeadline:
            DateTime.tryParse(j['acceptanceDeadline'] as String? ?? '')?.toLocal(),
        cancelReason: j['cancelReason'] as String? ?? '',
        cancelledBy: j['cancelledBy'] as String?,
        createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '')?.toLocal(),
        updatedAt: DateTime.tryParse(j['updatedAt'] as String? ?? '')?.toLocal(),
        closedAt: DateTime.tryParse(j['closedAt'] as String? ?? '')?.toLocal(),
        clientName: (j['clientName'] as String?)?.trim().isNotEmpty == true
            ? j['clientName'] as String
            : 'Заказчик',
        ownerName: (j['ownerName'] as String?)?.trim().isNotEmpty == true
            ? j['ownerName'] as String
            : 'Исполнитель',
        ownerRating: (j['ownerRating'] as num?)?.toDouble() ?? 0,
      );
}

/// Строка в ленте торга (ТЗ §2.9). Имена участников площадка не раскрывает —
/// только цена, место в списке и признак «это моя ставка».
class BidRow {
  const BidRow({
    required this.id,
    required this.price,
    required this.status,
    this.currency = 'AMD',
    this.rank = 0,
    this.comment = '',
    this.mine = false,
    this.score,
    this.createdAt,
  });

  final String id;
  final int price;
  final String currency;

  /// active | withdrawn | outbid | won | lost | expired
  final String status;

  /// Место по цене: 1 — лучшая.
  final int rank;
  final String comment;
  final bool mine;
  final double? score;
  final DateTime? createdAt;

  bool get isActive => status == 'active';
  bool get isWinner => status == 'won';

  factory BidRow.fromJson(Map<String, dynamic> j) => BidRow(
        id: j['id'] as String? ?? '',
        price: (j['price'] as num?)?.toInt() ?? 0,
        currency: j['currency'] as String? ?? 'AMD',
        status: j['status'] as String? ?? 'active',
        rank: j['rank'] as int? ?? 0,
        comment: j['comment'] as String? ?? '',
        mine: j['mine'] as bool? ?? false,
        score: (j['score'] as num?)?.toDouble(),
        createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '')?.toLocal(),
      );
}

/// Строка списка чатов (ТЗ §2.12).
class ChatRow {
  const ChatRow({
    required this.id,
    required this.jobId,
    this.jobTitle = '',
    this.peerName = 'Собеседник',
    this.kind = 'pre_deal',
    this.lastText = '',
    this.lastMessageAt,
    this.unread = 0,
  });

  final String id;
  final String jobId;
  final String jobTitle;
  final String peerName;

  /// pre_deal — до сделки (контакты маскируются), deal — чат сделки.
  final String kind;
  final String lastText;
  final DateTime? lastMessageAt;
  final int unread;

  bool get isDeal => kind == 'deal';

  factory ChatRow.fromJson(Map<String, dynamic> j) => ChatRow(
        id: j['id'] as String? ?? '',
        jobId: j['jobId'] as String? ?? '',
        jobTitle: j['jobTitle'] as String? ?? '',
        peerName: (j['peerName'] as String?)?.trim().isNotEmpty == true
            ? j['peerName'] as String
            : 'Собеседник',
        kind: j['kind'] as String? ?? 'pre_deal',
        lastText: j['lastText'] as String? ?? '',
        lastMessageAt: DateTime.tryParse(j['lastMessageAt'] as String? ?? '')?.toLocal(),
        unread: j['unread'] as int? ?? 0,
      );
}

/// Сообщение чата.
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.chatId,
    required this.text,
    required this.createdAt,
    this.senderId,
    this.kind = 'text',
  });

  final String id;
  final String chatId;
  final String? senderId;

  /// text | photo | system
  final String kind;
  final String text;
  final DateTime createdAt;

  bool get isSystem => kind == 'system';

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
        id: j['id'] as String? ?? '',
        chatId: j['chatId'] as String? ?? '',
        senderId: j['senderId'] as String?,
        kind: j['kind'] as String? ?? 'text',
        text: j['text'] as String? ?? '',
        createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '')?.toLocal() ??
            DateTime.now(),
      );
}

/// Результат отправки: сообщение и признак, что контакты были скрыты.
class SentMessage {
  const SentMessage({required this.message, required this.contactsMasked});

  final ChatMessage message;
  final bool contactsMasked;
}

/// Взаимная оценка после сделки (ТЗ §2.13).
class Review {
  const Review({
    required this.id,
    required this.stars,
    this.jobId = '',
    this.tags = const [],
    this.text = '',
    this.authorName = '',
    this.replyText = '',
    this.replyAt,
    this.publishedAt,
    this.createdAt,
  });

  final String id;
  final String jobId;
  final int stars;
  final List<String> tags;
  final String text;
  final String authorName;
  final String replyText;
  final DateTime? replyAt;
  final DateTime? publishedAt;
  final DateTime? createdAt;

  /// Отзыв виден посторонним. Скрытый ждёт оценки второй стороны или недели.
  bool get published => publishedAt != null;

  factory Review.fromJson(Map<String, dynamic> j) => Review(
        id: j['id'] as String? ?? '',
        jobId: j['jobId'] as String? ?? '',
        stars: j['stars'] as int? ?? 0,
        tags: ((j['tags'] as List?) ?? const []).map((e) => '$e').toList(),
        text: j['text'] as String? ?? '',
        authorName: j['authorName'] as String? ?? '',
        replyText: j['replyText'] as String? ?? '',
        replyAt: DateTime.tryParse(j['replyAt'] as String? ?? '')?.toLocal(),
        publishedAt: DateTime.tryParse(j['publishedAt'] as String? ?? '')?.toLocal(),
        createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '')?.toLocal(),
      );
}

/// Что показывать на экране оценки: чья очередь, какие отметки предлагать и
/// не оценил ли человек эту сделку раньше.
class ReviewForm {
  const ReviewForm({
    required this.dealId,
    this.authorRole = 'client',
    this.allowedTags = const [],
    this.canReview = false,
    this.targetName = '',
    this.mine,
  });

  final String dealId;

  /// client — я оценивал исполнителя, owner — заказчика.
  final String authorRole;
  final List<String> allowedTags;
  final bool canReview;
  final String targetName;
  final Review? mine;

  bool get alreadyLeft => mine != null;

  factory ReviewForm.fromJson(Map<String, dynamic> j) => ReviewForm(
        dealId: j['dealId'] as String? ?? '',
        authorRole: j['authorRole'] as String? ?? 'client',
        allowedTags: ((j['allowedTags'] as List?) ?? const []).map((e) => '$e').toList(),
        canReview: j['canReview'] as bool? ?? false,
        targetName: j['targetName'] as String? ?? '',
        mine: j['review'] == null
            ? null
            : Review.fromJson((j['review'] as Map).cast<String, dynamic>()),
      );
}

/// Карточка отзывов о человеке: список и сводка «★4,8 · 36 оценок».
class ReviewsPage {
  const ReviewsPage({this.items = const [], this.rating = 0, this.count = 0});

  final List<Review> items;
  final double rating;
  final int count;

  factory ReviewsPage.fromJson(Map<String, dynamic> j) => ReviewsPage(
        items: ((j['items'] as List?) ?? const [])
            .map((e) => Review.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
        rating: (j['rating'] as num?)?.toDouble() ?? 0,
        count: j['count'] as int? ?? 0,
      );
}

/// Ответ на отправленную оценку: опубликована ли она сразу и стоит ли
/// спросить, что пошло не так.
class ReviewResult {
  const ReviewResult({
    required this.review,
    this.published = false,
    this.asksWhatWentWrong = false,
  });

  final Review review;
  final bool published;
  final bool asksWhatWentWrong;
}

/// Единица техники исполнителя (ТЗ §2.5).
class Equipment {
  const Equipment({
    required this.id,
    this.categoryId = '',
    this.categoryName,
    this.brand = '',
    this.model = '',
    this.year,
    this.specs = const {},
    this.priceHour,
    this.priceShift,
    this.priceDay,
    this.minHours,
    this.delivery,
    this.crewSize = 0,
    this.crewPrice,
    this.photos = const [],
    this.status = 'draft',
    this.rejectReason = '',
    this.draftStep = 1,
    this.wins = 0,
  });

  final String id;
  final String categoryId;

  /// Название категории на трёх языках — приходит с сервера для карточки.
  final Map<String, dynamic>? categoryName;
  final String brand;
  final String model;
  final int? year;
  final Map<String, dynamic> specs;

  /// Тарифы аренды: пусто — техника только под задания.
  final int? priceHour;
  final int? priceShift;
  final int? priceDay;
  final int? minHours;
  final int? delivery;

  final int crewSize;
  final int? crewPrice;
  final List<String> photos;

  /// draft | pending | verified | unverified | rejected | archived
  final String status;
  final String rejectReason;
  final int draftStep;
  final int wins;

  String get title => '$brand $model'.trim();
  bool get isDraft => status == 'draft';
  bool get isPending => status == 'pending';
  bool get isVerified => status == 'verified';
  bool get isRejected => status == 'rejected';

  /// Участвует в откликах и ставках.
  bool get isActive => status == 'verified' || status == 'unverified';

  String categoryTitle(String lang) {
    final n = categoryName;
    if (n == null) return '';
    return (n[lang] ?? n['ru'] ?? '') as String;
  }

  factory Equipment.fromJson(Map<String, dynamic> j) => Equipment(
        id: j['id'] as String? ?? '',
        categoryId: j['categoryId'] as String? ?? '',
        categoryName: (j['categoryName'] as Map?)?.cast<String, dynamic>(),
        brand: j['brand'] as String? ?? '',
        model: j['model'] as String? ?? '',
        year: j['year'] as int?,
        specs: ((j['specs'] as Map?) ?? const {}).cast<String, dynamic>(),
        priceHour: (j['priceHour'] as num?)?.toInt(),
        priceShift: (j['priceShift'] as num?)?.toInt(),
        priceDay: (j['priceDay'] as num?)?.toInt(),
        minHours: j['minHours'] as int?,
        delivery: (j['delivery'] as num?)?.toInt(),
        crewSize: j['crewSize'] as int? ?? 0,
        crewPrice: (j['crewPrice'] as num?)?.toInt(),
        photos: ((j['photos'] as List?) ?? const []).map((e) => '$e').toList(),
        status: j['status'] as String? ?? 'draft',
        rejectReason: j['rejectReason'] as String? ?? '',
        draftStep: j['draftStep'] as int? ?? 1,
        wins: j['wins'] as int? ?? 0,
      );
}

/// Временная ссылка на загрузку файла в хранилище (ТЗ §2.5, ADR-5).
///
/// Файл уходит от клиента прямо в хранилище: фотографии весят мегабайты, и
/// прогонять их через наш сервер — лишний трафик и лишняя точка отказа.
class UploadLink {
  const UploadLink({
    required this.key,
    required this.uploadUrl,
    required this.publicUrl,
    this.expiresIn = 900,
  });

  final String key;
  final String uploadUrl;

  /// Постоянный адрес — именно он сохраняется в карточке техники.
  final String publicUrl;
  final int expiresIn;

  factory UploadLink.fromJson(Map<String, dynamic> j) => UploadLink(
        key: j['key'] as String? ?? '',
        uploadUrl: j['uploadUrl'] as String? ?? '',
        publicUrl: j['publicUrl'] as String? ?? '',
        expiresIn: j['expiresIn'] as int? ?? 900,
      );
}


/// Публичная карточка человека (ТЗ §2.3). Телефона здесь нет: до сделки он
/// скрыт, а в сделке приходит отдельно.
class PublicProfile {
  const PublicProfile({
    required this.id,
    this.name = '',
    this.city = '',
    this.verified = false,
    this.createdAt,
  });

  final String id;
  final String name;
  final String city;

  /// Документы проверены модерацией.
  final bool verified;
  final DateTime? createdAt;

  String get displayName => name.trim().isEmpty ? 'Пользователь' : name.trim();

  factory PublicProfile.fromJson(Map<String, dynamic> j) => PublicProfile(
        id: j['id'] as String? ?? '',
        name: j['name'] as String? ?? '',
        city: j['city'] as String? ?? '',
        verified: j['verified'] as bool? ?? false,
        createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '')?.toLocal(),
      );
}

/// Сводка «Мой бизнес» исполнителя (ТЗ §3.1). Цифры копятся сами из сделок.
class Business {
  const Business({
    this.period = 'month',
    this.income = 0,
    this.deals = 0,
    this.average = 0,
    this.currency = 'AMD',
    this.prevIncome = 0,
    this.delta = 0,
    this.deltaComparable = false,
    this.offers = 0,
    this.won = 0,
    this.completed = 0,
    this.winRate = 0,
    this.clients = const [],
  });

  final String period;
  final int income;
  final int deals;
  final int average;
  final String currency;
  final int prevIncome;

  /// Изменение дохода к прошлому периоду в процентах.
  final int delta;

  /// С нулём сравнивать нечего — тогда дельту не показываем.
  final bool deltaComparable;

  final int offers;
  final int won;
  final int completed;
  final double winRate;
  final List<BusinessClient> clients;

  factory Business.fromJson(Map<String, dynamic> j) {
    final funnel = (j['funnel'] as Map?)?.cast<String, dynamic>() ?? const {};
    return Business(
      period: j['period'] as String? ?? 'month',
      income: (j['income'] as num?)?.toInt() ?? 0,
      deals: j['deals'] as int? ?? 0,
      average: (j['average'] as num?)?.toInt() ?? 0,
      currency: j['currency'] as String? ?? 'AMD',
      prevIncome: (j['prevIncome'] as num?)?.toInt() ?? 0,
      delta: j['delta'] as int? ?? 0,
      deltaComparable: j['deltaComparable'] as bool? ?? false,
      offers: funnel['offers'] as int? ?? 0,
      won: funnel['won'] as int? ?? 0,
      completed: funnel['completed'] as int? ?? 0,
      winRate: (funnel['winRate'] as num?)?.toDouble() ?? 0,
      clients: ((j['clients'] as List?) ?? const [])
          .map((e) => BusinessClient.fromJson((e as Map).cast<String, dynamic>()))
          .toList(),
    );
  }
}

/// Строка клиентской базы.
class BusinessClient {
  const BusinessClient({
    required this.userId,
    this.name = '',
    this.deals = 0,
    this.total = 0,
    this.last,
    this.regular = false,
  });

  final String userId;
  final String name;
  final int deals;
  final int total;
  final DateTime? last;

  /// Три сделки и больше.
  final bool regular;

  factory BusinessClient.fromJson(Map<String, dynamic> j) => BusinessClient(
        userId: j['userId'] as String? ?? '',
        name: j['name'] as String? ?? '',
        deals: j['deals'] as int? ?? 0,
        total: (j['total'] as num?)?.toInt() ?? 0,
        last: DateTime.tryParse(j['last'] as String? ?? '')?.toLocal(),
        regular: j['regular'] as bool? ?? false,
      );
}

/// Сводка «Мои расходы» заказчика (ТЗ §3.2).
class Spending {
  const Spending({
    this.period = 'month',
    this.spent = 0,
    this.deals = 0,
    this.average = 0,
    this.currency = 'AMD',
    this.delta = 0,
    this.deltaComparable = false,
    this.byCategory = const [],
    this.owners = const [],
    this.saved = 0,
  });

  final String period;
  final int spent;
  final int deals;
  final int average;
  final String currency;
  final int delta;
  final bool deltaComparable;

  /// На что уходят деньги: земляные, перевозка, кран.
  final List<CategorySpend> byCategory;

  /// Исполнители, с которыми работал.
  final List<BusinessClient> owners;

  /// Сколько сэкономил торг: стартовая цена минус итоговая.
  final int saved;

  factory Spending.fromJson(Map<String, dynamic> j) => Spending(
        period: j['period'] as String? ?? 'month',
        spent: (j['spent'] as num?)?.toInt() ?? 0,
        deals: j['deals'] as int? ?? 0,
        average: (j['average'] as num?)?.toInt() ?? 0,
        currency: j['currency'] as String? ?? 'AMD',
        delta: j['delta'] as int? ?? 0,
        deltaComparable: j['deltaComparable'] as bool? ?? false,
        byCategory: ((j['byCategory'] as List?) ?? const [])
            .map((e) => CategorySpend.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
        owners: ((j['owners'] as List?) ?? const [])
            .map((e) => BusinessClient.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
        saved: (j['saved'] as num?)?.toInt() ?? 0,
      );
}

/// Расходы по одному виду работ.
class CategorySpend {
  const CategorySpend({this.categoryId = '', this.total = 0, this.deals = 0});

  final String categoryId;
  final int total;
  final int deals;

  factory CategorySpend.fromJson(Map<String, dynamic> j) => CategorySpend(
        categoryId: j['categoryId'] as String? ?? '',
        total: (j['total'] as num?)?.toInt() ?? 0,
        deals: j['deals'] as int? ?? 0,
      );
}

/// Карточка техники в очереди проверки (ТЗ §4.1). Документы видны только
/// модерации — в обычной карточке их нет.
class ModerationItem {
  const ModerationItem({
    required this.id,
    this.ownerId = '',
    this.title = '',
    this.year,
    this.photos = const [],
    this.docs = const [],
    this.categoryName,
    this.waitingHours = 0,
  });

  final String id;
  final String ownerId;
  final String title;
  final int? year;
  final List<String> photos;
  final List<String> docs;
  final Map<String, dynamic>? categoryName;

  /// Сколько часов карточка ждёт решения: обещали сутки.
  final int waitingHours;

  bool get overdue => waitingHours >= 24;

  String categoryTitle(String lang) {
    final n = categoryName;
    if (n == null) return '';
    return (n[lang] ?? n['ru'] ?? '') as String;
  }

  factory ModerationItem.fromJson(Map<String, dynamic> j) => ModerationItem(
        id: j['id'] as String? ?? '',
        ownerId: j['ownerId'] as String? ?? '',
        title: j['title'] as String? ?? '',
        year: j['year'] as int?,
        photos: ((j['photos'] as List?) ?? const []).map((e) => '$e').toList(),
        docs: ((j['docs'] as List?) ?? const []).map((e) => '$e').toList(),
        categoryName: (j['categoryName'] as Map?)?.cast<String, dynamic>(),
        waitingHours: j['waitingHours'] as int? ?? 0,
      );
}

/// День календаря занятости (ТЗ §3.1).
class BusyDay {
  const BusyDay({
    required this.day,
    this.source = 'manual',
    this.note = '',
    this.dealId = '',
    this.title = '',
  });

  final DateTime day;

  /// deal — день занят подтверждённой сделкой, manual — человек отметил сам.
  final String source;
  final String note;
  final String dealId;
  final String title;

  bool get fromDeal => source == 'deal';

  factory BusyDay.fromJson(Map<String, dynamic> j) => BusyDay(
        day: DateTime.tryParse(j['day'] as String? ?? '') ?? DateTime.now(),
        source: j['source'] as String? ?? 'manual',
        note: j['note'] as String? ?? '',
        dealId: j['dealId'] as String? ?? '',
        title: j['title'] as String? ?? '',
      );
}

/// Спор по сделке (ТЗ §4.1).
class Dispute {
  const Dispute({
    required this.id,
    this.dealId = '',
    this.jobId = '',
    this.jobTitle = '',
    this.reason = '',
    this.photos = const [],
    this.status = 'open',
    this.outcome = '',
    this.resolution = '',
    this.openedBy = '',
    this.clientName = '',
    this.ownerName = '',
    this.openedByClient = false,
    this.createdAt,
    this.resolvedAt,
  });

  final String id;
  final String dealId;
  final String jobId;
  final String jobTitle;
  final String reason;
  final List<String> photos;

  /// open — ждёт модератора, resolved — решение вынесено.
  final String status;

  /// client | owner | compromise
  final String outcome;

  /// Обоснование решения — его видят обе стороны.
  final String resolution;

  final String openedBy;
  final String clientName;
  final String ownerName;
  final bool openedByClient;
  final DateTime? createdAt;
  final DateTime? resolvedAt;

  bool get isOpen => status == 'open';

  String get outcomeLabel => switch (outcome) {
        'client' => 'в пользу заказчика',
        'owner' => 'в пользу исполнителя',
        'compromise' => 'компромисс',
        _ => '',
      };

  factory Dispute.fromJson(Map<String, dynamic> j) => Dispute(
        id: j['id'] as String? ?? '',
        dealId: j['dealId'] as String? ?? '',
        jobId: j['jobId'] as String? ?? '',
        jobTitle: j['jobTitle'] as String? ?? '',
        reason: j['reason'] as String? ?? '',
        photos: ((j['photos'] as List?) ?? const []).map((e) => '$e').toList(),
        status: j['status'] as String? ?? 'open',
        outcome: j['outcome'] as String? ?? '',
        resolution: j['resolution'] as String? ?? '',
        openedBy: j['openedBy'] as String? ?? '',
        clientName: j['clientName'] as String? ?? '',
        ownerName: j['ownerName'] as String? ?? '',
        openedByClient: j['openedByClient'] as bool? ?? false,
        createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '')?.toLocal(),
        resolvedAt: DateTime.tryParse(j['resolvedAt'] as String? ?? '')?.toLocal(),
      );
}

/// Жалоба на задание или человека (ТЗ §4.1, п.6).
///
/// Пока пожаловаться некуда, единственная реакция на обман — уйти с площадки.
class Complaint {
  const Complaint({
    required this.id,
    this.targetKind = 'job',
    this.targetId = '',
    this.targetTitle = '',
    this.reason = '',
    this.authorName = '',
    this.route = '',
    this.sameTarget = 0,
    this.status = 'open',
    this.action = '',
    this.createdAt,
  });

  final String id;

  /// job — задание, user — человек.
  final String targetKind;
  final String targetId;
  final String targetTitle;
  final String reason;
  final String authorName;

  /// Куда перейти, чтобы посмотреть спорный контент.
  final String route;

  /// Сколько всего жалоб на этот объект: одна может быть сведением счётов,
  /// пять — уже сигнал.
  final int sameTarget;

  final String status;
  final String action;
  final DateTime? createdAt;

  bool get isJob => targetKind == 'job';

  String get targetLabel => isJob ? 'Задание' : 'Пользователь';

  factory Complaint.fromJson(Map<String, dynamic> j) => Complaint(
        id: j['id'] as String? ?? '',
        targetKind: j['targetKind'] as String? ?? 'job',
        targetId: j['targetId'] as String? ?? '',
        targetTitle: j['targetTitle'] as String? ?? '',
        reason: j['reason'] as String? ?? '',
        authorName: j['authorName'] as String? ?? '',
        route: j['route'] as String? ?? '',
        sameTarget: (j['sameTarget'] as num?)?.toInt() ?? 0,
        status: j['status'] as String? ?? 'open',
        action: j['action'] as String? ?? '',
        createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '')?.toLocal(),
      );
}

/// Сводка площадки за период (ТЗ §4.1, п.1).
///
/// Без неё владелец узнаёт о проблеме от тех, кто уже ушёл.
class PlatformStats {
  const PlatformStats({
    this.days = 30,
    this.users = 0,
    this.jobs = 0,
    this.deals = 0,
    this.completed = 0,
    this.gmv = 0,
    this.avgCheck = 0,
    this.conversion = 0,
    this.openDisputes = 0,
    this.openComplaints = 0,
    this.prevUsers = 0,
    this.prevJobs = 0,
    this.prevDeals = 0,
    this.prevGmv = 0,
    this.prevConversion = 0,
  });

  final int days;
  final int users;
  final int jobs;
  final int deals;
  final int completed;
  final int gmv;

  /// Средний чек по завершённым сделкам.
  final int avgCheck;

  /// Доля заданий, дошедших до сделки, в процентах.
  final int conversion;

  final int openDisputes;
  final int openComplaints;

  /// Предыдущий такой же отрезок: цифра без сравнения ничего не значит.
  final int prevUsers;
  final int prevJobs;
  final int prevDeals;
  final int prevGmv;
  final int prevConversion;

  factory PlatformStats.fromJson(Map<String, dynamic> j) {
    final prev = ((j['prev'] as Map?) ?? const {}).cast<String, dynamic>();
    int n(Map<String, dynamic> m, String k) => (m[k] as num?)?.toInt() ?? 0;
    return PlatformStats(
      days: n(j, 'days'),
      users: n(j, 'users'),
      jobs: n(j, 'jobs'),
      deals: n(j, 'deals'),
      completed: n(j, 'completed'),
      gmv: n(j, 'gmv'),
      avgCheck: n(j, 'avgCheck'),
      conversion: n(j, 'conversion'),
      openDisputes: n(j, 'openDisputes'),
      openComplaints: n(j, 'openComplaints'),
      prevUsers: n(prev, 'users'),
      prevJobs: n(prev, 'jobs'),
      prevDeals: n(prev, 'deals'),
      prevGmv: n(prev, 'gmv'),
      prevConversion: n(prev, 'conversion'),
    );
  }
}

/// Карточка человека для модерации (ТЗ §4.1, п.3).
///
/// Телефон виден только здесь: модератор разбирает жалобы и должен связаться
/// с человеком. Раздел закрыт ролью.
class AdminUser {
  const AdminUser({
    required this.id,
    this.phone = '',
    this.name = '',
    this.city = '',
    this.roles = const [],
    this.verified = false,
    this.status = 'active',
    this.statusRu = '',
    this.reason = '',
    this.statusAt,
    this.createdAt,
    this.history = const [],
  });

  final String id;
  final String phone;
  final String name;
  final String city;
  final List<String> roles;
  final bool verified;

  /// active | frozen | banned
  final String status;
  final String statusRu;

  /// Причина ограничения — её видит и человек, и следующий модератор.
  final String reason;

  final DateTime? statusAt;
  final DateTime? createdAt;

  /// История решений: отличает единичный срыв от привычки.
  final List<AdminAction> history;

  bool get isActive => status == 'active';
  bool get isFrozen => status == 'frozen';
  bool get isBanned => status == 'banned';

  String get displayName => name.trim().isEmpty ? 'Без имени' : name;

  factory AdminUser.fromJson(Map<String, dynamic> j) => AdminUser(
        id: j['id'] as String? ?? '',
        phone: j['phone'] as String? ?? '',
        name: j['name'] as String? ?? '',
        city: j['city'] as String? ?? '',
        roles: ((j['roles'] as List?) ?? const []).map((e) => '$e').toList(),
        verified: j['verified'] as bool? ?? false,
        status: j['status'] as String? ?? 'active',
        statusRu: j['statusRu'] as String? ?? '',
        reason: j['reason'] as String? ?? '',
        statusAt: DateTime.tryParse(j['statusAt'] as String? ?? '')?.toLocal(),
        createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '')?.toLocal(),
        history: ((j['history'] as List?) ?? const [])
            .map((e) => AdminAction.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
      );
}

/// Запись журнала действий модерации (ТЗ §4.1, п.8).
class AdminAction {
  const AdminAction({
    required this.id,
    this.action = '',
    this.actionRu = '',
    this.reason = '',
    this.createdAt,
  });

  final String id;
  final String action;
  final String actionRu;
  final String reason;
  final DateTime? createdAt;

  factory AdminAction.fromJson(Map<String, dynamic> j) => AdminAction(
        id: j['id'] as String? ?? '',
        action: j['action'] as String? ?? '',
        actionRu: j['actionRu'] as String? ?? '',
        reason: j['reason'] as String? ?? '',
        createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '')?.toLocal(),
      );
}

/// Заявка на бейдж «Проверен» (ТЗ §2.3).
///
/// Бейдж — главный сигнал доверия в ленте: рядом с ним отклик читается иначе.
/// Поэтому он выдаётся после того, как документ посмотрел живой модератор.
class Verification {
  const Verification({
    this.id = '',
    this.docKind = 'passport',
    this.documents = const [],
    this.status = 'none',
    this.statusRu = '',
    this.reason = '',
    this.userId = '',
    this.userName = '',
    this.userPhone = '',
    this.createdAt,
    this.reviewedAt,
  });

  final String id;

  /// passport | license | other
  final String docKind;
  final List<String> documents;

  /// none — не подавалась, pending | approved | rejected
  final String status;
  final String statusRu;

  /// Причина отказа: без неё человек не поймёт, что переснять.
  final String reason;

  /// Заполняется только в очереди модерации: документ сверяют с профилем.
  final String userId;
  final String userName;
  final String userPhone;

  final DateTime? createdAt;
  final DateTime? reviewedAt;

  bool get isNone => status == 'none';
  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved';
  bool get isRejected => status == 'rejected';

  String get docKindRu => switch (docKind) {
        'passport' => 'Паспорт',
        'license' => 'Водительские права',
        _ => 'Другой документ',
      };

  factory Verification.fromJson(Map<String, dynamic> j) => Verification(
        id: j['id'] as String? ?? '',
        docKind: j['docKind'] as String? ?? 'passport',
        documents: ((j['documents'] as List?) ?? const []).map((e) => '$e').toList(),
        status: j['status'] as String? ?? 'none',
        statusRu: j['statusRu'] as String? ?? '',
        reason: j['reason'] as String? ?? '',
        userId: j['userId'] as String? ?? '',
        userName: j['userName'] as String? ?? '',
        userPhone: j['userPhone'] as String? ?? '',
        createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '')?.toLocal(),
        reviewedAt: DateTime.tryParse(j['reviewedAt'] as String? ?? '')?.toLocal(),
      );
}
