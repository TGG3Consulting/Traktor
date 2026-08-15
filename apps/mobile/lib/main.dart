import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app.dart';
import 'core/storage/local_store.dart';

Future<void> main() async {
  // Firebase (только FCM/Crashlytics/Analytics/RemoteConfig) инициализируется
  // на шаге сервисов Фазы 2 (после заведения Firebase-проекта).
  WidgetsFlutterBinding.ensureInitialized();
  // Адреса без решётки: app.homly.am/jobs/123 вместо app.homly.am/#/jobs/123.
  // Часть после решётки на сервер не отправляется, и бот мессенджера видит
  // пустую страницу вместо карточки задания — а ссылками делятся именно там
  // (ТЗ §4.2).
  usePathUrlStrategy();
  // Локальное хранилище: настройки (тема/язык/роль) переживают перезапуск.
  final prefs = await SharedPreferences.getInstance();
  runApp(
    ProviderScope(
      overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
      child: const TraktorApp(),
    ),
  );
}
