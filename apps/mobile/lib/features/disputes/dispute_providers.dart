import 'package:api_client/api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/session_refresh.dart';
import '../jobs/deal/deal_providers.dart';
import '../jobs/jobs_providers.dart';

/// Споры (ТЗ §4.1). Конфликт без арбитра — потерянный клиент с обеих сторон,
/// поэтому разбор ведётся внутри площадки.
final disputeOfDealProvider =
    FutureProvider.family<Dispute?, String>((ref, dealId) async {
  final token = ref.watch(accessTokenProvider);
  if (token.isEmpty) return null;
  try {
    return await ref
        .read(sessionRefresherProvider)
        .run((t) => ref.read(jobsApiProvider).dispute(t, dealId));
  } catch (_) {
    // Спора нет — это нормальное состояние сделки, а не ошибка экрана.
    return null;
  }
});

/// Очередь разбора у модератора.
final disputeQueueProvider = FutureProvider<List<Dispute>>((ref) async {
  final token = ref.watch(accessTokenProvider);
  if (token.isEmpty) return const [];
  return ref
      .read(sessionRefresherProvider)
      .run((t) => ref.read(jobsApiProvider).disputeQueue(t));
});

class DisputeActions {
  DisputeActions(this._ref);

  final Ref _ref;

  String _key(String action, String id) =>
      '$action-$id-${DateTime.now().microsecondsSinceEpoch}';

  Future<Dispute> open(String dealId, String reason, {List<String> photos = const []}) async {
    final d = await _ref.read(sessionRefresherProvider).run(
          (t) => _ref.read(jobsApiProvider).openDispute(t, dealId, reason,
              photos: photos, idempotencyKey: _key('dispute', dealId)),
        );
    _ref.invalidate(disputeOfDealProvider(dealId));
    _ref.invalidate(dealProvider(dealId));
    return d;
  }

  Future<Dispute> resolve(String disputeId,
      {required String outcome, required String resolution}) async {
    final d = await _ref.read(sessionRefresherProvider).run(
          (t) => _ref.read(jobsApiProvider).resolveDispute(t, disputeId,
              outcome: outcome,
              resolution: resolution,
              idempotencyKey: _key('resolve', disputeId)),
        );
    _ref.invalidate(disputeQueueProvider);
    return d;
  }
}

final disputeActionsProvider = Provider<DisputeActions>(DisputeActions.new);
