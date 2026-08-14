import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app.dart';
import 'core/storage/local_store.dart';

Future<void> main() async {
  // Firebase (только FCM/Crashlytics/Analytics/RemoteConfig) инициализируется
  // на шаге сервисов Фазы 2 (после заведения Firebase-проекта).
  WidgetsFlutterBinding.ensureInitialized();
  // Локальное хранилище: настройки (тема/язык/роль) переживают перезапуск.
  final prefs = await SharedPreferences.getInstance();
  runApp(
    ProviderScope(
      overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
      child: const TraktorApp(),
    ),
  );
}
