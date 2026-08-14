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
