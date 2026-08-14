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

    // Четыре таба; центральное место в панели пустое — там «висит» круглая
    // кнопка создания (как в прототипе). Раньше плюс был и пунктом панели,
    // и кнопкой поверх — получалось две одинаковые кнопки.
    final tabs = isClient
        ? [l.homeClient, 'Поиск', 'Сообщения', 'Профиль']
        : [l.homeOwner, 'Мои ставки', 'Сообщения', 'Профиль'];
    final icons = [
      isClient ? Icons.home_outlined : Icons.list_alt_outlined,
      isClient ? Icons.search : Icons.insights_outlined,
      Icons.chat_bubble_outline,
      Icons.person_outline,
    ];

    return Scaffold(
      body: SafeArea(
        child: _tab == 3 ? const _ProfileTab() : _Placeholder(title: tabs[_tab]),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _onCreate(context, isClient),
        backgroundColor: Theme.of(context).colorScheme.primary,
        shape: const CircleBorder(),
        tooltip: isClient ? 'Создать задание' : 'Быстрый отклик',
        child: const Icon(Icons.add, color: Colors.white, size: 28),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: BottomAppBar(
        shape: const CircularNotchedRectangle(),
        notchMargin: 8,
        height: 64,
        padding: EdgeInsets.zero,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _NavItem(icon: icons[0], label: tabs[0], selected: _tab == 0, onTap: () => setState(() => _tab = 0)),
            _NavItem(icon: icons[1], label: tabs[1], selected: _tab == 1, onTap: () => setState(() => _tab = 1)),
            const SizedBox(width: 56), // вырез под круглую кнопку
            _NavItem(icon: icons[2], label: tabs[2], selected: _tab == 2, onTap: () => setState(() => _tab = 2)),
            _NavItem(icon: icons[3], label: tabs[3], selected: _tab == 3, onTap: () => setState(() => _tab = 3)),
          ],
        ),
      ),
    );
  }

  /// Центральная кнопка: у заказчика — создание задания, у исполнителя —
  /// быстрый отклик. Экраны появятся в модуле «Задания»; пока честно говорим,
  /// что раздел ещё не готов, вместо кнопки, которая молча ничего не делает.
  void _onCreate(BuildContext context, bool isClient) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(isClient
            ? 'Создание задания появится в следующем обновлении'
            : 'Отклики появятся в следующем обновлении'),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}

/// Пункт нижней панели: иконка и подпись, активный подсвечен цветом бренда.
class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.onSurfaceVariant;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: color),
            ),
          ],
        ),
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
        const Text('Профиль', style: TkText.h1),
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
