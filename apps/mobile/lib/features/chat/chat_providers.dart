import 'package:api_client/api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/session_refresh.dart';
import '../jobs/jobs_providers.dart';

/// Список переписок (ТЗ §2.12).
final chatsProvider = FutureProvider<List<ChatRow>>((ref) async {
  final token = ref.watch(accessTokenProvider);
  if (token.isEmpty) return const [];
  return ref
      .read(sessionRefresherProvider)
      .run((t) => ref.read(jobsApiProvider).chats(t));
});

/// Карточка переписки: имя собеседника и режим (до сделки или в сделке).
final chatProvider = FutureProvider.family<ChatRow, String>((ref, chatId) async {
  ref.watch(accessTokenProvider);
  return ref
      .read(sessionRefresherProvider)
      .run((t) => ref.read(jobsApiProvider).chat(t, chatId));
});

/// История сообщений. Открытие экрана считается прочтением, поэтому после
/// загрузки обновляем список чатов — там пропадает бейдж непрочитанного.
final messagesProvider =
    FutureProvider.family<List<ChatMessage>, String>((ref, chatId) async {
  ref.watch(accessTokenProvider);
  final msgs = await ref
      .read(sessionRefresherProvider)
      .run((t) => ref.read(jobsApiProvider).messages(t, chatId));
  ref.invalidate(chatsProvider);
  return msgs;
});

/// Действия чата.
class ChatActions {
  ChatActions(this._ref);

  final Ref _ref;

  JobsApi get _api => _ref.read(jobsApiProvider);
  SessionRefresher get _refresher => _ref.read(sessionRefresherProvider);

  String _key(String action, String id) =>
      '$action-$id-${DateTime.now().microsecondsSinceEpoch}';

  /// Открыть переписку по заданию. ownerId нужен, когда пишет заказчик.
  Future<ChatRow> open(String jobId, {String? ownerId}) async {
    final chat = await _refresher.run((t) => _api.openChat(t, jobId,
        ownerId: ownerId, idempotencyKey: _key('chat', jobId)));
    _ref.invalidate(chatsProvider);
    return chat;
  }

  Future<SentMessage> send(String chatId, String text) async {
    final sent = await _refresher.run(
        (t) => _api.sendMessage(t, chatId, text, idempotencyKey: _key('msg', chatId)));
    _ref.invalidate(messagesProvider(chatId));
    _ref.invalidate(chatsProvider);
    return sent;
  }
}

final chatActionsProvider = Provider<ChatActions>(ChatActions.new);
