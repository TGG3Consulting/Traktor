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
      builder: (context, child) => _PhoneWidth(child: child),
    );
  }
}

/// Ограничение ширины на больших экранах (ТЗ §4.2, web-паритет).
///
/// Макет рисовался под телефон: растянутый на весь монитор он превращается в
/// строчки длиной в экран и кнопки шириной 1500 пикселей. Держим колонку
/// телефонной ширины по центру, а поля вокруг закрашиваем фоном.
class _PhoneWidth extends StatelessWidget {
  const _PhoneWidth({required this.child});

  final Widget? child;

  static const _maxWidth = 480.0;

  @override
  Widget build(BuildContext context) {
    final content = child ?? const SizedBox.shrink();
    if (MediaQuery.sizeOf(context).width <= _maxWidth) return content;

    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.surfaceContainerHighest,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _maxWidth),
          child: ClipRect(child: content),
        ),
      ),
    );
  }
}
