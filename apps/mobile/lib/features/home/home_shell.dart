import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:design_system/design_system.dart';
import 'package:traktor_mobile/l10n/app_localizations.dart';
import '../../core/app_settings.dart';
import '../auth/auth_controller.dart';
import '../moderation/moderation_screen.dart';
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
            TkTabItem(icon: TkIcons.magnifyingGlass, label: l.tabSearch),
            TkTabItem(icon: TkIcons.chatCircle, label: l.tabMessages),
            TkTabItem(icon: TkIcons.user, label: l.tabProfile),
          ]
        : [
            TkTabItem(icon: TkIcons.clipboardText, label: l.homeOwner),
            TkTabItem(icon: TkIcons.chartBar, label: l.tabMyBids),
            TkTabItem(icon: TkIcons.chatCircle, label: l.tabMessages),
            TkTabItem(icon: TkIcons.user, label: l.tabProfile),
          ];

    // На широком экране навигация уезжает вбок (ТЗ §1.8): нижняя панель на
    // мониторе стоит в тридцати сантиметрах от глаз и от курсора, а левый
    // край — там же, где взгляд начинает читать.
    final wide = !TkLayout.isPhone(context);

    // Лента на десктопе сама занимает ширину двумя колонками, остальные
    // вкладки держат колонку чтения: кнопка во весь монитор выглядит нелепо.
    final feedTab = (isClient && _tab == 1) || (!isClient && _tab == 0);
    Widget readable(Widget child) =>
        wide && !feedTab ? TkReadable(child: child) : child;

    final content = SafeArea(
        child: switch (_tab) {
          // Первая вкладка зависит от роли: заказчик ведёт свои задания,
          // исполнитель смотрит ленту (ТЗ §1.9).
          0 => isClient ? readable(const ClientJobsTab()) : const FeedTab(),
          1 => isClient
              // «Поиск» заказчика — та же лента; «Мои ставки» исполнителя —
              // его предложения по чужим заданиям.
              ? const FeedTab()
              : readable(const MyOffersTab()),
          2 => readable(const MessagesTab()),
          3 => readable(const _ProfileTab()),
          _ => readable(_Placeholder(title: items[_tab].label)),
        },
      );

    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: _tab,
              onDestinationSelected: (i) => setState(() => _tab = i),
              labelType: NavigationRailLabelType.all,
              leading: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: TkCreateButton(
                  tooltip: isClient ? l.createOrder : l.addMachine,
                  onPressed: () => _onCreate(context, isClient),
                ),
              ),
              destinations: [
                for (final it in items)
                  NavigationRailDestination(
                    icon: TkIcon(it.icon, size: 22),
                    label: Text(it.label),
                  ),
              ],
            ),
            VerticalDivider(width: 1, color: Theme.of(context).colorScheme.outlineVariant),
            Expanded(child: content),
          ],
        ),
      );
    }

    return Scaffold(
      body: content,
      floatingActionButton: TkCreateButton(
        tooltip: isClient ? l.createOrder : l.addMachine,
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
    final l = AppLocalizations.of(context);
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
        _notReady(context, l.rentMachine);
      case TkOrderType.transport:
        _notReady(context, l.transportAB);
      case TkOrderType.workers:
        _notReady(context, l.hireWorkers);
    }
  }

  void _notReady(BuildContext context, String what) {
    final l = AppLocalizations.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l.comingSoon(what)),
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
    final l = AppLocalizations.of(context);
    final settings = ref.watch(appSettingsProvider);
    final ctrl = ref.read(appSettingsProvider.notifier);
    final isClient = settings.role != TkRole.owner;

    return ListView(
      padding: TkSpace.screenMobile,
      children: [
        Text(l.tabProfile, style: TkText.h1),
        const SizedBox(height: 16),
        // Переключатель роли (ТЗ §2.4) — мгновенно перестраивает таб-бар.
        SegmentedButton<bool>(
          segments: [
            ButtonSegment(value: true, label: Text(l.iAmClient)),
            ButtonSegment(value: false, label: Text(l.iAmOwner)),
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
                title: Text(l.darkTheme),
                trailing: Switch(
                  value: settings.themeMode == ThemeMode.dark,
                  onChanged: (_) => ctrl.toggleTheme(),
                ),
              ),
              const Divider(height: 1),
              // Модерация: пункт появляется сам у тех, кому выдана роль.
              if (ref.watch(isModeratorProvider)) ...[
                ListTile(
                  leading: const TkIcon(TkIcons.shield),
                  title: Text(l.modEquipment),
                  trailing: const TkIcon(TkIcons.caretRight, size: 16),
                  onTap: () => context.push('/moderation'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const TkIcon(TkIcons.scales),
                  title: Text(l.modDisputes),
                  trailing: const TkIcon(TkIcons.caretRight, size: 16),
                  onTap: () => context.push('/moderation/disputes'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const TkIcon(TkIcons.flag),
                  title: Text(l.modComplaints),
                  trailing: const TkIcon(TkIcons.caretRight, size: 16),
                  onTap: () => context.push('/moderation/complaints'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const TkIcon(TkIcons.idCard),
                  title: Text(l.modVerifications),
                  trailing: const TkIcon(TkIcons.caretRight, size: 16),
                  onTap: () => context.push('/moderation/verifications'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const TkIcon(TkIcons.usersThree),
                  title: Text(l.modUsers),
                  trailing: const TkIcon(TkIcons.caretRight, size: 16),
                  onTap: () => context.push('/moderation/users'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const TkIcon(TkIcons.clipboardText),
                  title: Text(l.modCatalog),
                  trailing: const TkIcon(TkIcons.caretRight, size: 16),
                  onTap: () => context.push('/moderation/catalog'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const TkIcon(TkIcons.chartLineUp),
                  title: Text(l.modDashboard),
                  trailing: const TkIcon(TkIcons.caretRight, size: 16),
                  onTap: () => context.push('/moderation/dashboard'),
                ),
                const Divider(height: 1),
              ],
              // Заказчику — свои расходы, исполнителю — свой бизнес (ТЗ §3).
              if (isClient) ...[
                ListTile(
                  leading: const TkIcon(TkIcons.chartBar),
                  title: Text(l.mySpending),
                  trailing: const TkIcon(TkIcons.caretRight, size: 16),
                  onTap: () => context.push('/crm/spending'),
                ),
                const Divider(height: 1),
              ],
              // «Моя техника» — вход исполнителя в свой парк (ТЗ §2.5).
              if (!isClient) ...[
                ListTile(
                  leading: const TkIcon(TkIcons.chartBar),
                  title: Text(l.myBusiness),
                  trailing: const TkIcon(TkIcons.caretRight, size: 16),
                  onTap: () => context.push('/crm/business'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const TkIcon(TkIcons.calendar),
                  title: Text(l.myCalendar),
                  trailing: const TkIcon(TkIcons.caretRight, size: 16),
                  onTap: () => context.push('/crm/calendar'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const TkIcon(TkIcons.wrench),
                  title: Text(l.myEquipment),
                  trailing: const TkIcon(TkIcons.caretRight, size: 16),
                  onTap: () => context.push('/equipment'),
                ),
                const Divider(height: 1),
              ],
              // Бейдж «Проверен» (ТЗ §2.3): у проверенных чаще выбирают,
              // поэтому пункт виден всем, кто ещё не прошёл проверку.
              if (!(ref.watch(sessionProvider)?.user.verified ?? false)) ...[
                ListTile(
                  leading: const TkIcon(TkIcons.idCard),
                  title: Text(l.passVerification),
                  subtitle: Text(l.verifiedBadgeHint),
                  trailing: const TkIcon(TkIcons.caretRight, size: 16),
                  onTap: () => context.push('/profile/verification'),
                ),
                const Divider(height: 1),
              ],
              ListTile(
                leading: const TkIcon(TkIcons.bell),
                title: Text(l.notifications),
                trailing: const TkIcon(TkIcons.caretRight, size: 16),
                onTap: () => context.push('/settings/notifications'),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const TkIcon(TkIcons.globe),
                title: Text(l.languageLabel),
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
        // Уйти с площадки человек должен мочь (ТЗ §2.3): пункт неяркий, но
        // на виду, а не спрятан в переписке с поддержкой.
        TextButton(
          onPressed: () => context.push('/profile/delete'),
          child: Text(
            (ref.watch(sessionProvider)?.user.deleteAfter) == null
                ? l.deleteAccount
                : l.deletionPending,
            style: TkText.caption.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ),
        const SizedBox(height: 4),
        // Выход из аккаунта: чистит локальную сессию, возвращает на онбординг.
        TkButton(
          label: l.signOut,
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
