import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Абстракция push-уведомлений. За ней — реальный Firebase Cloud Messaging
/// (подключается, когда заведён Firebase-проект; по правилу 17 из Firebase у нас
/// только FCM/Crashlytics/Analytics/RemoteConfig), либо [FakePushService] для
/// локальной разработки без Firebase.
///
/// «Путь эвакуации» (инвариант архитектуры §2.3.14): смена транспорта пушей
/// (FCM → APNs/web-push) не трогает вызывающий код — меняется только реализация.
abstract class PushService {
  /// Запросить разрешение на уведомления (iOS и web — обязательно, Android 13+
  /// — POST_NOTIFICATIONS). true — разрешение есть.
  Future<bool> requestPermission();

  /// Актуальный push-токен устройства (null — нет разрешения/недоступно).
  Future<String?> getToken();

  /// Платформа устройства для регистрации на сервере: android|ios|web.
  String get platform;
}

/// Платформа клиента без обращения к dart:io (безопасно для web).
String detectPushPlatform() {
  if (kIsWeb) return 'web';
  switch (defaultTargetPlatform) {
    case TargetPlatform.iOS:
      return 'ios';
    default:
      return 'android';
  }
}

/// Fake: работает без Firebase. Выдаёт стабильный псевдо-токен и «разрешение
/// дано» — этого достаточно, чтобы прогонять сквозной флоу регистрации токена
/// против реального бэка ещё до подключения Firebase-проекта.
class FakePushService implements PushService {
  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<String?> getToken() async => 'fake-device-token';

  @override
  String get platform => detectPushPlatform();
}

/// Провайдер сервиса пушей. При подключении Firebase здесь появится
/// FirebasePushService(); вызывающий код не меняется.
final pushServiceProvider = Provider<PushService>((ref) => FakePushService());
