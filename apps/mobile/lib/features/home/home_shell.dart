import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:design_system/design_system.dart';
import 'package:traktor_mobile/l10n/app_localizations.dart';
import '../../core/app_settings.dart';
import '../auth/auth_controller.dart';

/// Каркас домашнего экрана: bottom-nav из 5 табов, набор зависит от роли
/// (ТЗ §1.9). Реальные экраны лент/сделок/CRM навешиваются в следующих фазах.
/// Таб «Профиль» уже даёт переключатели роли, темы и языка — это критерий
/// приёмки Фазы 2 (роли, темы, 3 языка) в рабочем виде.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});
  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final settings = ref.watch(appSettingsProvider);
    final isClient = settings.role != TkRole.owner;

    final tabs = isClient
        ? [l.homeClient, 'Поиск', '', 'Сообщения', 'Профиль']
        : [l.homeOwner, 'Мои ставки', '', 'Сообщения', 'Профиль'];
    final icons = [
      isClient ? Icons.home_outlined : Icons.list_alt_outlined,
      isClient ? Icons.search : Icons.insights_outlined,
      Icons.add,
      Icons.chat_bubble_outline,
      Icons.person_outline,
    ];

    return Scaffold(
      body: SafeArea(
        child: _tab == 4 ? const _ProfileTab() : _Placeholder(title: tabs[_tab]),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {},
        backgroundColor: Theme.of(context).colorScheme.primary,
        child: const Icon(Icons.add, color: Colors.white),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) {
          if (i == 2) return; // центральный FAB
          setState(() => _tab = i);
        },
        destinations: [
          for (var i = 0; i < 5; i++)
            NavigationDestination(
              icon: Icon(i == 2 ? Icons.add : icons[i]),
              label: i == 2 ? '' : tabs[i],
            ),
        ],
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.title});
  final String title;
  @override
  Widget build(BuildContext context) => Center(child: Text(title, style: TkText.h2));
}

/// Профиль: переключатель роли (перестраивает табы), тема, язык.
class _ProfileTab extends ConsumerWidget {
  const _ProfileTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final ctrl = ref.read(appSettingsProvider.notifier);
    final isClient = settings.role != TkRole.owner;

    return ListView(
      padding: TkSpace.screenMobile,
      children: [
        Text('Профиль', style: TkText.h1),
        const SizedBox(height: 16),
        // Переключатель роли (ТЗ §2.4) — мгновенно перестраивает таб-бар.
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: true, label: Text('Я заказчик')),
            ButtonSegment(value: false, label: Text('Я исполнитель')),
          ],
          selected: {isClient},
          onSelectionChanged: (s) => ctrl.setRole(s.first ? TkRole.client : TkRole.owner),
        ),
        const SizedBox(height: 20),
        TkCard(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.dark_mode_outlined),
                title: const Text('Тёмная тема'),
                trailing: Switch(
                  value: settings.themeMode == ThemeMode.dark,
                  onChanged: (_) => ctrl.toggleTheme(),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.language),
                title: const Text('Язык'),
                trailing: DropdownButton<String>(
                  value: (settings.locale ?? const Locale('ru')).languageCode,
                  underline: const SizedBox.shrink(),
                  items: const [
                    DropdownMenuItem(value: 'hy', child: Text('Հայերեն')),
                    DropdownMenuItem(value: 'ru', child: Text('Русский')),
                    DropdownMenuItem(value: 'en', child: Text('English')),
                  ],
                  onChanged: (v) => ctrl.setLocale(Locale(v ?? 'ru')),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        // Выход из аккаунта: чистит локальную сессию, возвращает на онбординг.
        TkButton(
          label: 'Выйти',
          kind: TkButtonKind.ghost,
          onPressed: () async {
            await ref.read(authControllerProvider.notifier).logout();
            if (context.mounted) context.go('/onboarding/language');
          },
        ),
      ],
    );
  }
}
