/// Модели ответов API (соответствуют схемам OpenAPI: User, Session, Problem).

class ApiUser {
  ApiUser({
    required this.id,
    required this.phone,
    required this.roles,
    required this.activeRole,
    this.name = '',
    this.avatarUrl,
    this.city,
    this.rating = 0,
    this.ratingCount = 0,
    this.verified = false,
  });

  final String id;
  final String phone;
  final String name;
  final String? avatarUrl;
  final String? city;
  final List<String> roles;
  final String activeRole;
  final double rating;
  final int ratingCount;
  final bool verified;

  factory ApiUser.fromJson(Map<String, dynamic> j) => ApiUser(
        id: j['id'] as String? ?? '',
        phone: j['phone'] as String? ?? '',
        name: j['name'] as String? ?? '',
        avatarUrl: j['avatarUrl'] as String?,
        city: j['city'] as String?,
        roles: (j['roles'] as List?)?.map((e) => e as String).toList() ?? const ['client'],
        activeRole: j['activeRole'] as String? ?? 'client',
        rating: (j['rating'] as num?)?.toDouble() ?? 0,
        ratingCount: j['ratingCount'] as int? ?? 0,
        verified: j['verified'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'phone': phone,
        'name': name,
        'avatarUrl': avatarUrl,
        'city': city,
        'roles': roles,
        'activeRole': activeRole,
        'rating': rating,
        'ratingCount': ratingCount,
        'verified': verified,
      };
}

class Session {
  Session({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresInSec,
    required this.user,
  });

  final String accessToken;
  final String refreshToken;
  final int expiresInSec;
  final ApiUser user;

  factory Session.fromJson(Map<String, dynamic> j) => Session(
        accessToken: j['accessToken'] as String,
        refreshToken: j['refreshToken'] as String,
        expiresInSec: j['expiresInSec'] as int? ?? 900,
        user: ApiUser.fromJson((j['user'] as Map).cast<String, dynamic>()),
      );

  Map<String, dynamic> toJson() => {
        'accessToken': accessToken,
        'refreshToken': refreshToken,
        'expiresInSec': expiresInSec,
        'user': user.toJson(),
      };
}

/// Ошибка API в формате problem+json (RFC 9457). `detail` — человекочитаемо,
/// годится прямо в тост.
class ApiException implements Exception {
  ApiException(this.status, this.detail);
  final int status;
  final String detail;

  @override
  String toString() => 'ApiException($status): $detail';
}
