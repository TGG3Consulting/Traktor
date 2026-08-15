import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'chat_providers.dart';

/// Открыть переписку по заданию и перейти в неё.
///
/// Одна точка входа на всё приложение: из отклика («Вопрос»), из деталки
/// задания и из сделки. Чат по паре «задание + исполнитель» всегда один,
/// поэтому повторное нажатие открывает ту же ветку, а не новую.
Future<void> openChatAndGo(
  BuildContext context,
  WidgetRef ref,
  String jobId, {
  String? ownerId,
}) async {
  try {
    final chat = await ref.read(chatActionsProvider).open(jobId, ownerId: ownerId);
    if (context.mounted) context.push('/chats/${chat.id}');
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Переписка не открылась: $e')),
      );
    }
  }
}

/// Кнопка-иконка «написать» рядом с основным действием: место в нижней
/// панели ограничено, а текстовая кнопка вытесняла бы главную.
class TkChatIconButton extends ConsumerWidget {
  const TkChatIconButton({super.key, required this.jobId, this.ownerId});

  final String jobId;
  final String? ownerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 52,
      height: 48,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(padding: EdgeInsets.zero),
        onPressed: () => openChatAndGo(context, ref, jobId, ownerId: ownerId),
        child: TkIcon(TkIcons.chatCircle, size: 20, color: scheme.onSurface),
      ),
    );
  }
}
