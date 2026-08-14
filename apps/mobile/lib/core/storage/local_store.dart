import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Локальное хранилище приложения (SharedPreferences). Инстанс резолвится один
/// раз в main() и прокидывается через override — весь код читает его синхронно.
///
/// Пока здесь — настройки (тема/язык/роль) и позже сессия. Офлайн-кэш доменных
/// данных и черновиков заказов (ТЗ §4.3) ляжет на Drift на своём шаге — это
/// хранилище остаётся точкой входа для локального состояния.
final sharedPrefsProvider = Provider<SharedPreferences>(
  (_) => throw UnimplementedError('sharedPrefsProvider должен быть переопределён в main()'),
);
