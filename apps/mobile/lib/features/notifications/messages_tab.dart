import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:traktor_mobile/l10n/app_localizations.dart';

import '../chat/chats_tab.dart';
import 'notifications_providers.dart';
import 'notifications_tab.dart';

/// Вкладка «Сообщения»: переписки и центр уведомлений (ТЗ §2.12 и §2.14,
/// прототип `chats` / `notifs`).
///
/// Два раздела под одним чипом-переключателем, как в прототипе: и то и другое —
/// «что мне пришло», разносить их по разным вкладкам значило бы заставить
/// человека помнить, где искать.
class MessagesTab extends ConsumerStatefulWidget {
  const MessagesTab({super.key});

  @override
  ConsumerState<MessagesTab> createState() => _MessagesTabState();
}

class _MessagesTabState extends ConsumerState<MessagesTab> {
  bool _chats = true;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final unread = ref.watch(notificationsProvider).valueOrNull?.unread ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          child: Row(
            children: [
              TkChip(
                label: l.tabChats,
                selected: _chats,
                onTap: () => setState(() => _chats = true),
              ),
              const SizedBox(width: 8),
              TkChip(
                label: unread > 0 ? l.notifWith(unread) : l.notifications,
                selected: !_chats,
                onTap: () => setState(() => _chats = false),
              ),
            ],
          ),
        ),
        Expanded(child: _chats ? const ChatsTab() : const NotificationsTab()),
      ],
    );
  }
}
