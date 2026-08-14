import 'package:api_client/api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/env.dart';
import '../../core/session_refresh.dart';
import '../auth/auth_controller.dart';

/// Клиент разделов catalog и orders.
final jobsApiProvider = Provider<JobsApi>((ref) => JobsApi(Env.apiBaseUrl));

/// Токен текущей сессии. Пусто — гость: лента и деталка всё равно работают
/// (ТЗ §2.1 «просто посмотреть»), а личные разделы требуют входа.
final accessTokenProvider = Provider<String>((ref) {
  return ref.watch(sessionProvider)?.accessToken ?? '';
});

/// Справочник видов работ (шаг 1 визарда). Держим в одном месте и кэшируем:
/// он нужен и в визарде, и в фильтрах ленты, и для подписи категории в карточке.
final workCategoriesProvider = FutureProvider<List<Category>>((ref) async {
  return ref.read(jobsApiProvider).categories(kind: 'work');
});

/// Категория по идентификатору — для подписей в карточках и деталке.
final categoryByIdProvider = Provider.family<Category?, String?>((ref, id) {
  if (id == null || id.isEmpty) return null;
  final list = ref.watch(workCategoriesProvider).valueOrNull ?? const <Category>[];
  for (final c in list) {
    if (c.id == id) return c;
    for (final child in c.children) {
      if (child.id == id) return child;
    }
  }
  return null;
});

/// Фильтры ленты (ТЗ §2.7). Хранятся отдельно от списка, чтобы смена чипа
/// перезапрашивала ленту, а не перерисовывала её вручную.
class FeedFilters {
  const FeedFilters({
    this.radiusKm = 25,
    this.mode = '',
    this.sort = 'new',
    this.query = '',
    this.categoryIds = const [],
    this.lat = 40.1872, // Ереван: до выдачи разрешения на гео показываем столицу,
    this.lng = 44.5152, // иначе лента была бы пустой без объяснения причин
  });

  final double radiusKm;
  final String mode; // '' | fixed | auction
  final String sort; // new | near | price | ending
  final String query;
  final List<String> categoryIds;
  final double lat;
  final double lng;

  FeedFilters copyWith({
    double? radiusKm,
    String? mode,
    String? sort,
    String? query,
    List<String>? categoryIds,
    double? lat,
    double? lng,
  }) =>
      FeedFilters(
        radiusKm: radiusKm ?? this.radiusKm,
        mode: mode ?? this.mode,
        sort: sort ?? this.sort,
        query: query ?? this.query,
        categoryIds: categoryIds ?? this.categoryIds,
        lat: lat ?? this.lat,
        lng: lng ?? this.lng,
      );
}

final feedFiltersProvider = StateProvider<FeedFilters>((ref) => const FeedFilters());

/// Лента заданий по текущим фильтрам.
final feedProvider = FutureProvider<List<Job>>((ref) async {
  final f = ref.watch(feedFiltersProvider);
  final token = ref.watch(accessTokenProvider);
  return ref.read(jobsApiProvider).feed(
        token: token.isEmpty ? null : token,
        lat: f.lat,
        lng: f.lng,
        radiusKm: f.radiusKm,
        categoryIds: f.categoryIds,
        mode: f.mode.isEmpty ? null : f.mode,
        query: f.query,
        sort: f.sort,
      );
});

/// Мои задания и черновики (главная заказчика).
///
/// Запрос идёт через обновление сессии: истёкший access не должен выкидывать
/// человека из приложения — токен молча обновляется, и список загружается.
final myJobsProvider = FutureProvider<List<Job>>((ref) async {
  final token = ref.watch(accessTokenProvider);
  if (token.isEmpty) return const [];
  return ref
      .read(sessionRefresherProvider)
      .run((t) => ref.read(jobsApiProvider).myJobs(t));
});

/// Деталка задания.
final jobProvider = FutureProvider.family<Job, String>((ref, id) async {
  final token = ref.watch(accessTokenProvider);
  return ref.read(jobsApiProvider).byId(id, token: token.isEmpty ? null : token);
});
