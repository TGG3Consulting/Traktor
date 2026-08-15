import 'package:api_client/api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/session_refresh.dart';
import '../jobs/jobs_providers.dart';

/// Список «Моя техника» (ТЗ §2.5).
final myEquipmentProvider = FutureProvider<List<Equipment>>((ref) async {
  final token = ref.watch(accessTokenProvider);
  if (token.isEmpty) return const [];
  return ref
      .read(sessionRefresherProvider)
      .run((t) => ref.read(jobsApiProvider).myEquipment(t));
});

/// Справочник техники для первого шага визарда: дерево категорий ветви unit.
final unitCategoriesProvider = FutureProvider<List<Category>>((ref) async {
  return ref.read(jobsApiProvider).categories(kind: 'unit');
});

/// Категория техники по идентификатору — нужна визарду для specTemplate.
final unitCategoryByIdProvider = Provider.family<Category?, String?>((ref, id) {
  if (id == null || id.isEmpty) return null;
  final list = ref.watch(unitCategoriesProvider).valueOrNull ?? const <Category>[];
  Category? find(List<Category> items) {
    for (final c in items) {
      if (c.id == id) return c;
      final inner = find(c.children);
      if (inner != null) return inner;
    }
    return null;
  }

  return find(list);
});

/// Действия над техникой.
class EquipmentActions {
  EquipmentActions(this._ref);

  final Ref _ref;

  JobsApi get _api => _ref.read(jobsApiProvider);
  SessionRefresher get _refresher => _ref.read(sessionRefresherProvider);

  String _key(String action, String id) =>
      '$action-$id-${DateTime.now().microsecondsSinceEpoch}';

  Future<Equipment> startDraft({String? categoryId}) async {
    final e = await _refresher.run((t) => _api.createEquipmentDraft(t,
        categoryId: categoryId, idempotencyKey: _key('equip-draft', 'new')));
    _ref.invalidate(myEquipmentProvider);
    return e;
  }

  Future<Equipment> patch(
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
  }) async {
    final e = await _refresher.run((t) => _api.patchEquipment(
          t,
          id,
          categoryId: categoryId,
          brand: brand,
          model: model,
          year: year,
          specs: specs,
          priceHour: priceHour,
          priceShift: priceShift,
          priceDay: priceDay,
          minHours: minHours,
          delivery: delivery,
          crewSize: crewSize,
          crewPrice: crewPrice,
          photos: photos,
          docs: docs,
          draftStep: draftStep,
          idempotencyKey: _key('equip-patch', id),
        ));
    _ref.invalidate(myEquipmentProvider);
    return e;
  }

  Future<Equipment> submit(String id) async {
    final e = await _refresher
        .run((t) => _api.submitEquipment(t, id, idempotencyKey: _key('equip-submit', id)));
    _ref.invalidate(myEquipmentProvider);
    return e;
  }

  Future<Equipment> archive(String id) async {
    final e = await _refresher
        .run((t) => _api.archiveEquipment(t, id, idempotencyKey: _key('equip-arch', id)));
    _ref.invalidate(myEquipmentProvider);
    return e;
  }
}

final equipmentActionsProvider = Provider<EquipmentActions>(EquipmentActions.new);
