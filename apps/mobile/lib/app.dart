import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:design_system/design_system.dart';
import 'package:traktor_mobile/l10n/app_localizations.dart';
import 'core/app_settings.dart';
import 'core/router.dart';

/// Корень приложения. Тема — из design_system (брендбук), обе обязательны.
/// Локаль — из настроек (hy/ru/en), тема-режим — светлая/тёмная/системная.
class TraktorApp extends ConsumerWidget {
  const TraktorApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    return MaterialApp.router(
      title: 'Traktor',
      debugShowCheckedModeBanner: false,
      theme: TkTheme.light,
      darkTheme: TkTheme.dark,
      themeMode: settings.themeMode,
      locale: settings.locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      routerConfig: appRouter,
    );
  }
}
