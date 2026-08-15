import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../features/jobs/jobs_providers.dart';
import 'env.dart';
import 'session_refresh.dart';

/// Живые обновления торга и переписки (ADR-6).
///
/// Аукцион теряет смысл, если о новой ставке узнаёшь при следующем заходе на
/// экран: торг идёт минутами. Поэтому экран подписывается на канал задания и
/// получает цену и новый срок за доли секунды.
///
/// Говорим с Centrifugo его JSON-протоколом напрямую: официальный клиент тянет
/// зависимости, которые не собираются под веб, а нужен нам всего один сценарий —
/// подключиться, подписаться, слушать.
class RealtimeClient {
  RealtimeClient(this._ref);

  final Ref _ref;

  WebSocketChannel? _socket;
  StreamSubscription<dynamic>? _sub;
  int _commandId = 0;

  /// Каналы, на которые подписаны, и их слушатели.
  final _listeners = <String, Set<void Function(Map<String, dynamic>)>>{};

  /// Подписаться на канал. Возвращает функцию отписки — экран вызывает её,
  /// когда закрывается, иначе соединение копит мёртвых слушателей.
  /// [subscriptionToken] нужен закрытым каналам (переписка): Centrifugo
  /// пускает в них только по билету, выданному сервисом-владельцем данных.
  Future<void Function()> subscribe(
    String channel,
    void Function(Map<String, dynamic> event) onEvent, {
    String? subscriptionToken,
  }) async {
    _listeners.putIfAbsent(channel, () => {}).add(onEvent);

    try {
      await _ensureConnected();
      _send({
        'id': ++_commandId,
        'subscribe': {
          'channel': channel,
          if (subscriptionToken != null && subscriptionToken.isNotEmpty)
            'token': subscriptionToken,
        },
      });
    } catch (_) {
      // Живые обновления — приятное дополнение, а не условие работы: если
      // канал недоступен, экран просто обновляется при заходе.
    }

    return () {
      final set = _listeners[channel];
      set?.remove(onEvent);
      if (set != null && set.isEmpty) {
        _listeners.remove(channel);
        _send({
          'id': ++_commandId,
          'unsubscribe': {'channel': channel},
        });
      }
      if (_listeners.isEmpty) _close();
    };
  }

  Future<void> _ensureConnected() async {
    if (_socket != null) return;

    final token = await _ref.read(sessionRefresherProvider).run(
          (t) => _ref.read(jobsApiProvider).realtimeToken(t),
        );

    final socket = WebSocketChannel.connect(Uri.parse(Env.realtimeUrl));
    _socket = socket;
    _sub = socket.stream.listen(
      _onMessage,
      onDone: _reset,
      onError: (_) => _reset(),
      cancelOnError: true,
    );

    _send({
      'id': ++_commandId,
      'connect': {'token': token},
    });
  }

  void _onMessage(dynamic raw) {
    if (raw is! String || raw.isEmpty) return;
    // Centrifugo шлёт по одному JSON в строке; пустая строка — пинг, на него
    // отвечаем пустым объектом, иначе сервер закроет соединение.
    for (final line in const LineSplitter().convert(raw)) {
      if (line.trim().isEmpty || line.trim() == '{}') {
        _socket?.sink.add('{}');
        continue;
      }
      Map<String, dynamic> msg;
      try {
        msg = jsonDecode(line) as Map<String, dynamic>;
      } catch (_) {
        continue;
      }

      final push = msg['push'] as Map<String, dynamic>?;
      if (push == null) continue;
      final channel = push['channel'] as String? ?? '';
      final data = (push['pub'] as Map<String, dynamic>?)?['data'];
      if (data is! Map) continue;

      for (final listener in _listeners[channel] ?? const {}) {
        listener(data.cast<String, dynamic>());
      }
    }
  }

  void _send(Map<String, dynamic> command) {
    try {
      _socket?.sink.add(jsonEncode(command));
    } catch (_) {
      // Соединение уже закрыто — переподключимся при следующей подписке.
    }
  }

  void _reset() {
    _sub?.cancel();
    _sub = null;
    _socket = null;
  }

  void _close() {
    _socket?.sink.close();
    _reset();
  }
}

final realtimeProvider = Provider<RealtimeClient>((ref) {
  final client = RealtimeClient(ref);
  ref.onDispose(client._close);
  return client;
});
