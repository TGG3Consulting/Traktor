import 'package:api_client/api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/session_refresh.dart';
import '../jobs/jobs_providers.dart';

/// Жалобы на контент (ТЗ §4.1, п.6).
///
/// Пока пожаловаться некуда, единственная реакция на обман — уйти с площадки
/// и рассказать знакомым. Жалоба даёт модерации повод посмотреть.

/// Очередь жалоб у модератора: старые сверху.
final complaintQueueProvider = FutureProvider<List<Complaint>>((ref) async {
  final token = ref.watch(accessTokenProvider);
  if (token.isEmpty) return const [];
  return ref
      .read(sessionRefresherProvider)
      .run((t) => ref.read(jobsApiProvider).complaintQueue(t));
});

/// Сводка площадки (ТЗ §4.1, п.1). Период задаётся днями.
final platformStatsProvider =
    FutureProvider.family<PlatformStats, int>((ref, days) async {
  final token = ref.watch(accessTokenProvider);
  if (token.isEmpty) return const PlatformStats();
  return ref
      .read(sessionRefresherProvider)
      .run((t) => ref.read(jobsApiProvider).dashboard(t, days: days));
});

class ComplaintActions {
  ComplaintActions(this._ref);

  final Ref _ref;

  String _key(String action, String id) =>
      '$action-$id-${DateTime.now().microsecondsSinceEpoch}';

  Future<Complaint> complain({
    required String targetKind,
    required String targetId,
    required String reason,
  }) {
    return _ref.read(sessionRefresherProvider).run(
          (t) => _ref.read(jobsApiProvider).complain(
                t,
                targetKind: targetKind,
                targetId: targetId,
                reason: reason,
                idempotencyKey: _key('complain', targetId),
              ),
        );
  }

  Future<Complaint> review(String id,
      {required String action, required String note}) async {
    final c = await _ref.read(sessionRefresherProvider).run(
          (t) => _ref.read(jobsApiProvider).reviewComplaint(
                t,
                id,
                action: action,
                note: note,
                idempotencyKey: _key('review', id),
              ),
        );
    _ref.invalidate(complaintQueueProvider);
    return c;
  }
}

final complaintActionsProvider = Provider<ComplaintActions>(ComplaintActions.new);
