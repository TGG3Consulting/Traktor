import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:design_system/design_system.dart';
import 'package:traktor_mobile/l10n/app_localizations.dart';
import '../../core/app_settings.dart';
import '../auth/auth_controller.dart';
import '../notifications/messages_tab.dart';
import '../jobs/client_jobs_tab.dart';
import '../jobs/create/wizard_controller.dart';
import '../jobs/feed_tab.dart';
import '../jobs/offers/my_offers_tab.dart';

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

    // Панель 1:1 с прототипом: четыре пункта и вырез по центру под круглую
    // кнопку. Иконки — Phosphor (правило 8), подписи и порядок — из прототипа.
    final items = isClient
        ? [
            TkTabItem(icon: TkIcons.house, label: l.homeClient),
            const TkTabItem(icon: TkIcons.magnifyingGlass, label: 'Поиск'),
            const TkTabItem(icon: TkIcons.chatCircle, label: 'Сообщения'),
            const TkTabItem(icon: TkIcons.user, label: 'Профиль'),
          ]
        : [
            TkTabItem(icon: TkIcons.clipboardText, label: l.homeOwner),
            const TkTabItem(icon: TkIcons.chartBar, label: 'Мои ставки'),
            const TkTabItem(icon: TkIcons.chatCircle, label: 'Сообщения'),
            const TkTabItem(icon: TkIcons.user, label: 'Профиль'),
          ];

    return Scaffold(
      body: SafeArea(
        child: switch (_tab) {
          // Первая вкладка зависит от роли: заказчик ведёт свои задания,
          // исполнитель смотрит ленту (ТЗ §1.9).
          0 => isClient ? const ClientJobsTab() : const FeedTab(),
          1 => isClient
              // «Поиск» заказчика — та же лента; «Мои ставки» исполнителя —
              // его предложения по чужим заданиям.
              ? const FeedTab()
              : const MyOffersTab(),
          2 => const MessagesTab(),
          3 => const _ProfileTab(),
          _ => _Placeholder(title: items[_tab].label),
        },
      ),
      floatingActionButton: TkCreateButton(
        tooltip: isClient ? 'Создать заказ' : 'Добавить технику',
        onPressed: () => _onCreate(context, isClient),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: TkTabBar(
        items: items,
        currentIndex: _tab,
        onSelected: (i) => setState(() => _tab = i),
      ),
    );
  }

  /// Круглая кнопка: у заказчика — выбор типа заказа (ТЗ §5.1), у исполнителя —
  /// добавление техники. Экраны этих сценариев делаются в соответствующих
  /// модулях; пока раздел не готов, честно говорим об этом, а не молчим.
  Future<void> _onCreate(BuildContext context, bool isClient) async {
    if (!isClient) {
      context.push('/equipment/new');
      return;
    }
    final type = await showTkOrderTypeSheet(context);
    if (type == null || !context.mounted) return;
    switch (type) {
      case TkOrderType.job:
        // Начинаем новый визард: старый черновик остаётся на главной и
        // открывается оттуда отдельно.
        ref.read(wizardControllerProvider.notifier).startNew();
        context.go('/jobs/create/1');
      case TkOrderType.rental:
        _notReady(context, 'Аренда техники');
      case TkOrderType.transport:
        _notReady(context, 'Перевозка А→Б');
      case TkOrderType.workers:
        _notReady(context, 'Заказ разнорабочих');
    }
  }

  void _notReady(BuildContext context, String what) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$what — в работе, появится в следующем обновлении'),
        duration: const Duration(seconds: 2),
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
                leading: const TkIcon(TkIcons.moon),
                title: const Text('Тёмная тема'),
                trailing: Switch(
                  value: settings.themeMode == ThemeMode.dark,
                  onChanged: (_) => ctrl.toggleTheme(),
                ),
              ),
              const Divider(height: 1),
              // «Моя техника» — вход исполнителя в свой парк (ТЗ §2.5).
              if (!isClient) ...[
                ListTile(
                  leading: const TkIcon(TkIcons.wrench),
                  title: const Text('Моя техника'),
                  trailing: const TkIcon(TkIcons.caretRight, size: 16),
                  onTap: () => context.push('/equipment'),
                ),
                const Divider(height: 1),
              ],
              ListTile(
                leading: const TkIcon(TkIcons.bell),
                title: const Text('Уведомления'),
                trailing: const TkIcon(TkIcons.caretRight, size: 16),
                onTap: () => context.push('/settings/notifications'),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const TkIcon(TkIcons.globe),
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
