import 'package:api_client/api_client.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'complaint_providers.dart';

/// Очередь жалоб (ТЗ §4.1, п.6).
///
/// Модератор видит, на что жалуются, кто пожаловался и сколько таких жалоб на
/// том же объекте: одна может быть сведением счётов, пять — уже сигнал.
class ComplaintQueueScreen extends ConsumerWidget {
  const ComplaintQueueScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final queue = ref.watch(complaintQueueProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Жалобы'),
        leading: IconButton(
          tooltip: 'Назад',
          onPressed: () => context.canPop() ? context.pop() : context.go('/home'),
          icon: TkIcon(TkIcons.arrowLeft, size: 20, color: scheme.onSurface),
        ),
      ),
      body: queue.when(
        loading: () => const TkSkeletonList(count: 3),
        error: (e, _) => TkErrorState(
          message: '$e',
          onRetry: () => ref.invalidate(complaintQueueProvider),
        ),
        data: (items) {
          if (items.isEmpty) {
            return const TkEmptyState(
              icon: TkIcons.flag,
              title: 'Жалоб нет',
              description: 'Разобранные жалобы уходят отсюда сами',
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(complaintQueueProvider),
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) => _ComplaintCard(complaint: items[i]),
            ),
          );
        },
      ),
    );
  }
}

class _ComplaintCard extends ConsumerStatefulWidget {
  const _ComplaintCard({required this.complaint});

  final Complaint complaint;

  @override
  ConsumerState<_ComplaintCard> createState() => _ComplaintCardState();
}

class _ComplaintCardState extends ConsumerState<_ComplaintCard> {
  bool _busy = false;

  Future<void> _review() async {
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (_) => _ReviewDialog(complaint: widget.complaint),
    );
    if (result == null) return;

    setState(() => _busy = true);
    try {
      await ref
          .read(complaintActionsProvider)
          .review(widget.complaint.id, action: result.$1, note: result.$2);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Жалоба закрыта')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Не получилось: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = widget.complaint;

    return TkCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              TkIcon(c.isJob ? TkIcons.clipboardText : TkIcons.user,
                  size: 16, color: scheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  c.targetTitle.isEmpty ? c.targetLabel : c.targetTitle,
                  style: TkText.h3,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // Повторяющиеся жалобы на один объект — главный признак того,
              // что смотреть нужно сейчас.
              if (c.sameTarget > 1)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: TkColors.warning.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text('${c.sameTarget} жалобы',
                      style: TkText.caption.copyWith(fontWeight: FontWeight.w600)),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: TkRadius.cardR,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'От ${c.authorName}'
                  '${c.createdAt != null ? ' · ${tkShortDate(c.createdAt)}' : ''}',
                  style: TkText.caption.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(c.reason, style: TkText.body),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: c.route.isEmpty ? null : () => context.push(c.route),
                  child: Text(c.isJob ? 'Смотреть задание' : 'Смотреть профиль'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: _busy ? null : _review,
                  child: _busy
                      ? const SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Разобрать'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReviewDialog extends StatefulWidget {
  const _ReviewDialog({required this.complaint});

  final Complaint complaint;

  @override
  State<_ReviewDialog> createState() => _ReviewDialogState();
}

class _ReviewDialogState extends State<_ReviewDialog> {
  final _note = TextEditingController();
  String _action = 'dismissed';

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isJob = widget.complaint.isJob;

    return AlertDialog(
      title: const Text('Решение по жалобе'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                TkChip(
                  label: 'Не подтвердилась',
                  selected: _action == 'dismissed',
                  onTap: () => setState(() => _action = 'dismissed'),
                ),
                if (isJob)
                  TkChip(
                    label: 'Снять задание',
                    selected: _action == 'removed',
                    onTap: () => setState(() => _action = 'removed'),
                  ),
                TkChip(
                  label: 'Предупреждение',
                  selected: _action == 'warned',
                  onTap: () => setState(() => _action = 'warned'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TkTextField(
              controller: _note,
              label: 'Комментарий',
              hint: 'Что именно нарушено — это увидят автор жалобы и нарушитель',
              maxLines: 3,
              maxLength: 500,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 6),
            Text(
              _action == 'removed'
                  ? 'Задание уйдёт из ленты, автор получит уведомление с причиной.'
                  : 'Автор жалобы узнает о решении — иначе в следующий раз он '
                      'не пожалуется, а уйдёт.',
              style: TkText.caption.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, (_action, _note.text.trim())),
          child: const Text('Применить'),
        ),
      ],
    );
  }
}
