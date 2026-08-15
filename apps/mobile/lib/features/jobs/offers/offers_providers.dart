import 'package:api_client/api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/session_refresh.dart';
import '../jobs_providers.dart';

/// Отклики по заданию — список для заказчика (ТЗ §2.10).
final jobOffersProvider = FutureProvider.family<List<Offer>, String>((ref, jobId) async {
  final token = ref.watch(accessTokenProvider);
  if (token.isEmpty) return const [];
  return ref
      .read(sessionRefresherProvider)
      .run((t) => ref.read(jobsApiProvider).jobOffers(t, jobId));
});

/// Свой отклик исполнителя по заданию: по нему деталка решает, показывать
/// кнопку отклика или уже отправленное предложение.
final myOfferProvider = FutureProvider.family<Offer?, String>((ref, jobId) async {
  final token = ref.watch(accessTokenProvider);
  if (token.isEmpty) return null;
  return ref
      .read(sessionRefresherProvider)
      .run((t) => ref.read(jobsApiProvider).myOfferForJob(t, jobId));
});

/// Все предложения исполнителя — вкладка «Мои ставки».
final myOffersProvider = FutureProvider<List<Offer>>((ref) async {
  final token = ref.watch(accessTokenProvider);
  if (token.isEmpty) return const [];
  return ref
      .read(sessionRefresherProvider)
      .run((t) => ref.read(jobsApiProvider).myOffers(t));
});

/// Действия с откликами. Отдельный класс, а не разрозненные вызовы по экранам:
/// после каждого действия нужно обновить одни и те же списки, и забытый
/// invalidate — самая частая причина «нажал, а ничего не изменилось».
class OfferActions {
  OfferActions(this._ref);

  final Ref _ref;

  JobsApi get _api => _ref.read(jobsApiProvider);
  SessionRefresher get _refresher => _ref.read(sessionRefresherProvider);

  String _key(String action, String id) =>
      '$action-$id-${DateTime.now().microsecondsSinceEpoch}';

  Future<Offer> make(
    String jobId, {
    required String kind,
    required int price,
    String comment = '',
    String eta = '',
    String? unitId,
  }) async {
    final offer = await _refresher.run((t) => _api.makeOffer(
          t,
          jobId,
          kind: kind,
          price: price,
          comment: comment,
          eta: eta,
          unitId: unitId,
          idempotencyKey: _key('offer', jobId),
        ));
    _refreshAll(jobId);
    return offer;
  }

  Future<Offer> withdraw(String jobId, String offerId) async {
    final offer = await _refresher
        .run((t) => _api.withdrawOffer(t, offerId, idempotencyKey: _key('withdraw', offerId)));
    _refreshAll(jobId);
    return offer;
  }

  Future<Offer> accept(String jobId, String offerId) async {
    final offer = await _refresher
        .run((t) => _api.acceptOffer(t, offerId, idempotencyKey: _key('accept', offerId)));
    _refreshAll(jobId);
    return offer;
  }

  Future<Offer> decline(String jobId, String offerId, {String reason = ''}) async {
    final offer = await _refresher.run((t) =>
        _api.declineOffer(t, offerId, reason: reason, idempotencyKey: _key('decline', offerId)));
    _refreshAll(jobId);
    return offer;
  }

  Future<Offer> counter(String jobId, String offerId, int price) async {
    final offer = await _refresher.run(
        (t) => _api.counterOffer(t, offerId, price, idempotencyKey: _key('counter', offerId)));
    _refreshAll(jobId);
    return offer;
  }

  void _refreshAll(String jobId) {
    _ref.invalidate(jobOffersProvider(jobId));
    _ref.invalidate(myOfferProvider(jobId));
    _ref.invalidate(myOffersProvider);
    _ref.invalidate(jobProvider(jobId));
    _ref.invalidate(myJobsProvider);
    _ref.invalidate(feedProvider);
  }
}

final offerActionsProvider = Provider<OfferActions>(OfferActions.new);
