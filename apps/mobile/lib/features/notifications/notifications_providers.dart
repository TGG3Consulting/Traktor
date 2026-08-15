import 'package:api_client/api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/env.dart';
import '../../core/session_refresh.dart';
import '../jobs/jobs_providers.dart';

final notificationsApiProvider =
    Provider<NotificationsApi>((ref) => NotificationsApi(Env.apiBaseUrl));

/// Центр уведомлений (ТЗ §2.14): лента событий и счётчик непрочитанного.
final notificationsProvider = FutureProvider<NotificationsPage>((ref) async {
  final token = ref.watch(accessTokenProvider);
  if (token.isEmpty) return const NotificationsPage();
  return ref
      .read(sessionRefresherProvider)
      .run((t) => ref.read(notificationsApiProvider).feed(t));
});

class NotificationActions {
  NotificationActions(this._ref);

  final Ref _ref;

  /// Пустой список — «прочитать все».
  Future<void> markRead({List<String> ids = const []}) async {
    final key = 'read-${DateTime.now().microsecondsSinceEpoch}';
    await _ref.read(sessionRefresherProvider).run(
        (t) => _ref.read(notificationsApiProvider).markRead(t, ids: ids, idempotencyKey: key));
    _ref.invalidate(notificationsProvider);
  }
}

final notificationActionsProvider =
    Provider<NotificationActions>(NotificationActions.new);
