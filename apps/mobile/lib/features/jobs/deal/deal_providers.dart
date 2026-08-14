import 'package:api_client/api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/session_refresh.dart';
import '../jobs_providers.dart';
import '../offers/offers_providers.dart';

/// Сделка по заданию (ТЗ §2.11). null — сделки ещё нет.
final dealByJobProvider = FutureProvider.family<Deal?, String>((ref, jobId) async {
  final token = ref.watch(accessTokenProvider);
  if (token.isEmpty) return null;
  return ref
      .read(sessionRefresherProvider)
      .run((t) => ref.read(jobsApiProvider).dealByJob(t, jobId));
});

/// Одна сделка по её идентификатору.
final dealProvider = FutureProvider.family<Deal, String>((ref, dealId) async {
  // Следим за токеном: после входа-выхода сделку нужно перечитать под новым
  // пользователем, иначе экран покажет чужие данные из кэша.
  ref.watch(accessTokenProvider);
  return ref
      .read(sessionRefresherProvider)
      .run((t) => ref.read(jobsApiProvider).deal(t, dealId));
});

/// Мои сделки в обеих ролях.
final myDealsProvider = FutureProvider<List<Deal>>((ref) async {
  final token = ref.watch(accessTokenProvider);
  if (token.isEmpty) return const [];
  return ref
      .read(sessionRefresherProvider)
      .run((t) => ref.read(jobsApiProvider).myDeals(t));
});

/// Действия по сделке. Как и с откликами: после каждого шага обновляются одни
/// и те же списки, поэтому обновление собрано в одном месте.
class DealActions {
  DealActions(this._ref);

  final Ref _ref;

  JobsApi get _api => _ref.read(jobsApiProvider);
  SessionRefresher get _refresher => _ref.read(sessionRefresherProvider);

  String _key(String action, String id) =>
      '$action-$id-${DateTime.now().microsecondsSinceEpoch}';

  Future<Deal> confirm(String jobId) async {
    final deal = await _refresher
        .run((t) => _api.confirmDeal(t, jobId, idempotencyKey: _key('deal', jobId)));
    _refresh(jobId, deal.id);
    return deal;
  }

  Future<Deal> step(String jobId, String dealId, String status, {String note = ''}) async {
    final deal = await _refresher.run((t) => _api.dealStep(t, dealId, status,
        note: note, idempotencyKey: _key('step-$status', dealId)));
    _refresh(jobId, dealId);
    return deal;
  }

  Future<Deal> cancel(String jobId, String dealId, String reason) async {
    final deal = await _refresher.run((t) =>
        _api.cancelDeal(t, dealId, reason, idempotencyKey: _key('cancel', dealId)));
    _refresh(jobId, dealId);
    return deal;
  }

  void _refresh(String jobId, String dealId) {
    _ref.invalidate(dealProvider(dealId));
    _ref.invalidate(dealByJobProvider(jobId));
    _ref.invalidate(myDealsProvider);
    _ref.invalidate(jobProvider(jobId));
    _ref.invalidate(myJobsProvider);
    _ref.invalidate(jobOffersProvider(jobId));
    _ref.invalidate(feedProvider);
  }
}

final dealActionsProvider = Provider<DealActions>(DealActions.new);
