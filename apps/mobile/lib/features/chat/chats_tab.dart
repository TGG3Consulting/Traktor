import 'package:api_client/api_client.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'chat_providers.dart';

/// Вкладка «Сообщения» — список переписок (ТЗ §2.12, прототип `chats`).
///
/// Порядок — по последнему сообщению: чат, в котором только что написали,
/// человек ищет первым. Непрочитанные показаны бейджем, как в мессенджерах.
class ChatsTab extends ConsumerWidget {
  const ChatsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chats = ref.watch(chatsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Text('Сообщения', style: TkText.h1),
        ),
        Expanded(
          child: chats.when(
            loading: () => const TkSkeletonList(count: 3),
            error: (e, _) => TkErrorState(
              message: '$e',
              onRetry: () => ref.invalidate(chatsProvider),
            ),
            data: (list) {
              if (list.isEmpty) {
                return const TkEmptyState(
                  icon: TkIcons.chatCircle,
                  title: 'Переписок пока нет',
                  description:
                      'Напишите по заданию из отклика или деталки — переписка появится здесь',
                );
              }
              return RefreshIndicator(
                onRefresh: () async => ref.invalidate(chatsProvider),
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 24),
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const Divider(height: 1, indent: 70),
                  itemBuilder: (context, i) => _ChatRowTile(row: list[i]),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ChatRowTile extends StatelessWidget {
  const _ChatRowTile({required this.row});

  final ChatRow row;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final unread = row.unread > 0;

    return InkWell(
      onTap: () => context.push('/chats/${row.id}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 11),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _Avatar(name: row.peerName),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          row.jobTitle.isEmpty
                              ? row.peerName
                              : '${row.peerName} · ${row.jobTitle}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TkText.body.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        tkChatStamp(row.lastMessageAt),
                        style: TkText.caption.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          row.lastText.isEmpty ? 'Переписка открыта' : row.lastText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TkText.caption.copyWith(
                            color: unread ? scheme.onSurface : scheme.onSurfaceVariant,
                            fontWeight: unread ? FontWeight.w600 : FontWeight.w400,
                          ),
                        ),
                      ),
                      if (unread) ...[
                        const SizedBox(width: 8),
                        _UnreadBadge(count: row.unread),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Аватар из инициалов: фото профиля появится вместе с загрузкой изображений,
/// а до тех пор две буквы отличают собеседников лучше одинаковых заглушек.
class _Avatar extends StatelessWidget {
  const _Avatar({required this.name});

  final String name;

  static const size = 46.0;

  String get _initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return (parts[0].characters.first + parts[1].characters.first).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        shape: BoxShape.circle,
      ),
      child: Text(
        _initials,
        style: TkText.body.copyWith(fontWeight: FontWeight.w600, color: scheme.onSurface),
      ),
    );
  }
}

class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(minWidth: 19),
        height: 19,
        padding: const EdgeInsets.symmetric(horizontal: 5),
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          color: TkColors.primary,
          borderRadius: BorderRadius.all(Radius.circular(10)),
        ),
        child: Text(
          count > 99 ? '99+' : '$count',
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white),
        ),
      );
}
