import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/auth/auth_controller.dart';
import 'storage/session_store.dart';

/// Обновление access-токена по 401 (ТЗ §2.2, план Фазы 2).
///
/// Access живёт 15 минут — без обновления человек, оставивший приложение
/// открытым, получал бы «сессия недействительна» посреди работы. Здесь запрос
/// повторяется один раз с новым токеном; если и refresh не принят, сессия
/// чистится и приложение честно просит войти снова.
class SessionRefresher {
  SessionRefresher(this._ref);

  final Ref _ref;

  /// Один общий запрос обновления на всё приложение: если четыре экрана разом
  /// получили 401, refresh-токен должен быть использован ровно один раз —
  /// иначе сервер посчитает повтор попыткой кражи (reuse detection) и закроет
  /// всю сессию.
  Future<Session?>? _inFlight;

  /// Выполняет [action] с текущим токеном. При 401 обновляет сессию и
  /// повторяет попытку ещё раз.
  Future<T> run<T>(Future<T> Function(String token) action) async {
    final session = _ref.read(sessionProvider);
    if (session == null) return action('');

    try {
      return await action(session.accessToken);
    } on ApiException catch (e) {
      if (e.status != 401) rethrow;

      final refreshed = await _refresh(session.refreshToken);
      if (refreshed == null) {
        await _dropSession();
        rethrow;
      }
      return action(refreshed.accessToken);
    }
  }

  Future<Session?> _refresh(String refreshToken) {
    return _inFlight ??= _doRefresh(refreshToken).whenComplete(() => _inFlight = null);
  }

  Future<Session?> _doRefresh(String refreshToken) async {
    try {
      final session = await _ref.read(authApiProvider).refresh(refreshToken);
      _ref.read(sessionProvider.notifier).state = session;
      unawaited(_ref.read(sessionStoreProvider).save(session));
      return session;
    } on ApiException {
      return null;
    }
  }

  Future<void> _dropSession() async {
    _ref.read(sessionProvider.notifier).state = null;
    await _ref.read(sessionStoreProvider).clear();
  }
}

final sessionRefresherProvider = Provider<SessionRefresher>(SessionRefresher.new);
