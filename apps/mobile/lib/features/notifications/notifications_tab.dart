import 'package:api_client/api_client.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:traktor_mobile/l10n/app_localizations.dart';

import 'notifications_providers.dart';

/// Центр уведомлений (ТЗ §2.14, прототип `notifs`).
///
/// Push доходит не всегда — телефон был выключен, разрешение не выдано, баннер
/// смахнули. Здесь событие есть всегда, и по нажатию открывается тот экран, о
/// котором оно говорит.
class NotificationsTab extends ConsumerWidget {
  const NotificationsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final page = ref.watch(notificationsProvider);
    final unread = page.valueOrNull?.unread ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (unread > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => ref.read(notificationActionsProvider).markRead(),
                  child: Text(l.readAll),
                ),
              ],
            ),
          ),
        Expanded(
          child: page.when(
            loading: () => const TkSkeletonList(count: 3),
            error: (e, _) => TkErrorState(
              message: '$e',
              onRetry: () => ref.invalidate(notificationsProvider),
            ),
            data: (data) {
              if (data.items.isEmpty) {
                return TkEmptyState(
                  icon: TkIcons.bell,
                  title: l.noNotifTitle,
                  description: l.noNotifDesc,
                );
              }
              return RefreshIndicator(
                onRefresh: () async => ref.invalidate(notificationsProvider),
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 24),
                  itemCount: data.items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1, indent: 60),
                  itemBuilder: (context, i) => _NotificationTile(item: data.items[i]),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _NotificationTile extends ConsumerWidget {
  const _NotificationTile({required this.item});

  final AppNotification item;

  /// Иконка по типу события: Phosphor, без эмодзи (правило 8).
  static String _icon(String kind) => switch (kind) {
        'offer' => TkIcons.handshake,
        'auction' => TkIcons.chartBar,
        'deal' => TkIcons.clipboardText,
        'message' => TkIcons.chatCircle,
        'review' => TkIcons.starFill,
        'job' => TkIcons.wrench,
        _ => TkIcons.bell,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: () async {
        // Открытие — это и есть прочтение; экран назначения важнее галочки,
        // поэтому переходим сразу, не дожидаясь ответа сервера.
        if (!item.read) {
          unawaited(ref.read(notificationActionsProvider).markRead(ids: [item.id]));
        }
        if (item.route.isNotEmpty) context.push(item.route);
      },
      child: Container(
        color: item.read ? null : scheme.primary.withValues(alpha: 0.05),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                shape: BoxShape.circle,
              ),
              child: TkIcon(_icon(item.kind), size: 18, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TkText.body.copyWith(
                            fontWeight: item.read ? FontWeight.w400 : FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        tkChatStamp(item.createdAt),
                        style: TkText.caption.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                  if (item.body.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      item.body,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TkText.caption.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Запуск без ожидания: отметка прочтения не должна задерживать переход.
void unawaited(Future<void> future) {
  future.catchError((_) {});
}
