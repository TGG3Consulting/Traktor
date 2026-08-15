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

/// Ограничение ширины на больших экранах (ТЗ §1.8, §4.2).
///
/// Макет рисовался под телефон: растянутый на весь монитор он превращается
/// в строки длиной в экран. Но и сжимать всё до телефонной колонки нельзя —
/// на десктопе половина экрана оставалась пустой, а лента листалась по одному
/// заданию. Поэтому предел ширины зависит от того, что показывает экран:
/// двухколоночные экраны сами занимают доступное место, остальные держат
/// колонку чтения.
class _PhoneWidth extends StatelessWidget {
  const _PhoneWidth({required this.child});

  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final content = child ?? const SizedBox.shrink();
    final width = MediaQuery.sizeOf(context).width;
    if (width <= TkLayout.readable) return content;

    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.surfaceContainerHighest,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: TkLayout.contentMax),
          child: ClipRect(child: content),
        ),
      ),
    );
  }
}
