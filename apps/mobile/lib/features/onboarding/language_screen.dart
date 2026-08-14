import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:design_system/design_system.dart';
import '../../core/app_settings.dart';

/// §2.1 Онбординг · язык. Названия языков — на самих языках, без флагов.
/// Выбор реально переключает локаль приложения.
class LanguageScreen extends ConsumerWidget {
  const LanguageScreen({super.key});

  static const _langs = [
    (Locale('hy'), 'Հայերեն'),
    (Locale('ru'), 'Русский'),
    (Locale('en'), 'English'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: TkSpace.screenMobile,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Լեզու · Язык · Language', style: TkText.h2, textAlign: TextAlign.center),
              const SizedBox(height: 20),
              for (final (locale, name) in _langs) ...[
                TkCard(
                  onTap: () {
                    ref.read(appSettingsProvider.notifier).setLocale(locale);
                    context.go('/onboarding/role');
                  },
                  padding: const EdgeInsets.all(18),
                  child: Center(
                    child: Text(name, style: TkText.h3),
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
