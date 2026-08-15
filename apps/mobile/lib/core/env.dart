/// Конфигурация окружения. Задаётся при сборке через --dart-define, чтобы
/// один и тот же код работал в dev (fake) и на реальном сервере.
///
///   flutter run --dart-define=REAL_BACKEND=true \
///               --dart-define=API_BASE_URL=https://api.traktor.am/v1
class Env {
  Env._();

  /// false = локальный fake-вход (код 000000), не требует сервера.
  /// true  = реальный сервис identity по [apiBaseUrl].
  static const bool useRealBackend =
      bool.fromEnvironment('REAL_BACKEND', defaultValue: false);

  /// Базовый URL API. Для Android-эмулятора к локальному серверу — 10.0.2.2.
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8080/v1',
  );

  /// Адрес живых обновлений (Centrifugo, ADR-6). Пусто — экраны обновляются
  /// только при заходе, всё остальное работает как обычно.
  static const String realtimeUrl = String.fromEnvironment(
    'REALTIME_URL',
    defaultValue: 'ws://localhost:18000/connection/websocket',
  );
}
