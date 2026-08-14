import 'dart:convert';
import 'package:api_client/api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'local_store.dart';

/// Локальное хранение сессии (токены + профиль), чтобы вход переживал перезапуск.
/// Пока — SharedPreferences; на шаге безопасности заменим на secure-storage
/// (Keychain/Keystore) — интерфейс вызова при этом не изменится.
class SessionStore {
  SessionStore(this._p);
  final SharedPreferences _p;

  static const _key = 'auth.session';

  Session? load() {
    final s = _p.getString(_key);
    if (s == null || s.isEmpty) return null;
    try {
      return Session.fromJson((jsonDecode(s) as Map).cast<String, dynamic>());
    } catch (_) {
      return null; // повреждённые данные — как будто входа нет
    }
  }

  Future<void> save(Session session) => _p.setString(_key, jsonEncode(session.toJson()));

  Future<void> clear() => _p.remove(_key);
}

final sessionStoreProvider =
    Provider<SessionStore>((ref) => SessionStore(ref.read(sharedPrefsProvider)));
