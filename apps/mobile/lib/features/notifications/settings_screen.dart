import 'package:api_client/api_client.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/session_refresh.dart';
import '../jobs/jobs_providers.dart';
import 'notifications_providers.dart';

/// Настройки уведомлений (ТЗ §2.14, прототип `notif_settings`).
///
/// Тумблеры по группам, а не один рубильник: иначе человек отключает всё разом
/// и пропускает важное. Выключенная группа глушит только push — событие всё
/// равно остаётся в центре уведомлений.
final notificationPrefsProvider = FutureProvider<NotificationPrefs>((ref) async {
  final token = ref.watch(accessTokenProvider);
  if (token.isEmpty) return const NotificationPrefs();
  return ref
      .read(sessionRefresherProvider)
      .run((t) => ref.read(notificationsApiProvider).prefs(t));
});

class NotificationSettingsScreen extends ConsumerWidget {
  const NotificationSettingsScreen({super.key});

  Future<void> _save(
    BuildContext context,
    WidgetRef ref, {
    bool? auctions,
    bool? deals,
    bool? chat,
    bool? newJobs,
    bool? marketing,
    bool? quietHours,
    bool? outbidAlways,
  }) async {
    try {
      await ref.read(sessionRefresherProvider).run(
            (t) => ref.read(notificationsApiProvider).savePrefs(
                  t,
                  auctions: auctions,
                  deals: deals,
                  chat: chat,
                  newJobs: newJobs,
                  marketing: marketing,
                  quietHours: quietHours,
                  outbidAlways: outbidAlways,
                ),
          );
      ref.invalidate(notificationPrefsProvider);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Настройка не сохранилась: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final prefs = ref.watch(notificationPrefsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Уведомления'),
        leading: IconButton(
          tooltip: 'Назад',
          onPressed: () => context.canPop() ? context.pop() : context.go('/home'),
          icon: TkIcon(TkIcons.arrowLeft, size: 20, color: scheme.onSurface),
        ),
      ),
      body: prefs.when(
        loading: () => const TkSkeletonList(count: 2),
        error: (e, _) => TkErrorState(
          message: '$e',
          onRetry: () => ref.invalidate(notificationPrefsProvider),
        ),
        data: (p) => ListView(
          padding: TkSpace.screenMobile,
          children: [
            TkCard(
              child: Column(
                children: [
                  _Row(
                    icon: TkIcons.chartBar,
                    title: 'Аукционы',
                    subtitle: 'Ставки, продления, итоги торга',
                    value: p.auctions,
                    onChanged: (v) => _save(context, ref, auctions: v),
                  ),
                  const Divider(height: 1),
                  _Row(
                    icon: TkIcons.handshake,
                    title: 'Сделки',
                    subtitle: 'Отклики, выбор исполнителя, шаги работы',
                    value: p.deals,
                    onChanged: (v) => _save(context, ref, deals: v),
                  ),
                  const Divider(height: 1),
                  _Row(
                    icon: TkIcons.chatCircle,
                    title: 'Сообщения',
                    subtitle: 'Новые сообщения в переписке',
                    value: p.chat,
                    onChanged: (v) => _save(context, ref, chat: v),
                  ),
                  const Divider(height: 1),
                  _Row(
                    icon: TkIcons.clipboardText,
                    title: 'Новые задания',
                    subtitle: 'Подходящие задания рядом',
                    value: p.newJobs,
                    onChanged: (v) => _save(context, ref, newJobs: v),
                  ),
                  const Divider(height: 1),
                  _Row(
                    icon: TkIcons.bell,
                    title: 'Новости площадки',
                    subtitle: 'Акции и полезные новости — по желанию',
                    value: p.marketing,
                    onChanged: (v) => _save(context, ref, marketing: v),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            TkCard(
              child: Column(
                children: [
                  _Row(
                    icon: TkIcons.moon,
                    title: 'Тихие часы',
                    subtitle:
                        'С ${p.quietFrom}:00 до ${p.quietTo}:00 телефон не звенит. '
                        'События всё равно ждут в уведомлениях',
                    value: p.quietHours,
                    onChanged: (v) => _save(context, ref, quietHours: v),
                  ),
                  const Divider(height: 1),
                  _Row(
                    icon: TkIcons.lightning,
                    title: 'Будить, если перебили ставку',
                    subtitle: 'На аукционе минуты решают — исключение из тишины',
                    value: p.outbidAlways,
                    enabled: p.quietHours,
                    onChanged: (v) => _save(context, ref, outbidAlways: v),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Выключенная группа отключает только push. Само событие всё равно '
              'попадёт в центр уведомлений — ничего не потеряется.',
              style: TkText.caption.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final String icon;
  final String title;
  final String subtitle;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: ListTile(
        leading: TkIcon(icon, size: 20, color: scheme.onSurfaceVariant),
        title: Text(title, style: TkText.body),
        subtitle: Text(
          subtitle,
          style: TkText.caption.copyWith(color: scheme.onSurfaceVariant),
        ),
        trailing: Switch(value: value, onChanged: enabled ? onChanged : null),
      ),
    );
  }
}
