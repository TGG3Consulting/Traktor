import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';

void main() {
  // Firebase (только FCM/Crashlytics/Analytics/RemoteConfig) инициализируется
  // здесь на шаге сервисов Фазы 2. Пока — чистый запуск клиента.
  runApp(const ProviderScope(child: TraktorApp()));
}
