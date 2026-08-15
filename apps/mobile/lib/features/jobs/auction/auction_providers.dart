import 'package:api_client/api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/session_refresh.dart';
import '../deal/deal_providers.dart';
import '../jobs_providers.dart';

/// Лента торга по заданию (ТЗ §2.9). Открыта всем, кто видит задание.
final jobBidsProvider = FutureProvider.family<List<BidRow>, String>((ref, jobId) async {
  final token = ref.watch(accessTokenProvider);
  return ref
      .read(jobsApiProvider)
      .jobBids(jobId, token: token.isEmpty ? null : token);
});

/// Своя ставка по заданию: по ней экран решает, что показать исполнителю.
final myBidProvider = FutureProvider.family<BidRow?, String>((ref, jobId) async {
  final token = ref.watch(accessTokenProvider);
  if (token.isEmpty) return null;
  return ref
      .read(sessionRefresherProvider)
      .run((t) => ref.read(jobsApiProvider).myBidForJob(t, jobId));
});

/// Действия аукциона.
class AuctionActions {
  AuctionActions(this._ref);

  final Ref _ref;

  JobsApi get _api => _ref.read(jobsApiProvider);
  SessionRefresher get _refresher => _ref.read(sessionRefresherProvider);

  String _key(String action, String id) =>
      '$action-$id-${DateTime.now().microsecondsSinceEpoch}';

  Future<BidRow> place(String jobId, int price, {String comment = ''}) async {
    final bid = await _refresher.run((t) => _api.placeBid(t, jobId,
        price: price, comment: comment, idempotencyKey: _key('bid', jobId)));
    _refresh(jobId);
    return bid;
  }

  Future<BidRow> withdraw(String jobId, String bidId) async {
    final bid = await _refresher
        .run((t) => _api.withdrawBid(t, bidId, idempotencyKey: _key('bid-withdraw', bidId)));
    _refresh(jobId);
    return bid;
  }

  Future<BidRow> accept(String jobId, String bidId) async {
    final bid = await _refresher
        .run((t) => _api.acceptBid(t, bidId, idempotencyKey: _key('bid-accept', bidId)));
    _refresh(jobId);
    return bid;
  }

  Future<Job> declineAll(String jobId) async {
    final j = await _refresher.run(
        (t) => _api.declineAllBids(t, jobId, idempotencyKey: _key('decline-all', jobId)));
    _refresh(jobId);
    return j;
  }

  void _refresh(String jobId) {
    _ref.invalidate(jobBidsProvider(jobId));
    _ref.invalidate(myBidProvider(jobId));
    _ref.invalidate(jobProvider(jobId));
    _ref.invalidate(myJobsProvider);
    _ref.invalidate(dealByJobProvider(jobId));
    _ref.invalidate(feedProvider);
  }
}

final auctionActionsProvider = Provider<AuctionActions>(AuctionActions.new);
