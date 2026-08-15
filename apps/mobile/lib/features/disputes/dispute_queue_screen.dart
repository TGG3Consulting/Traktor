import 'package:api_client/api_client.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'dispute_providers.dart';

/// Очередь разбора споров (ТЗ §4.1, п.4).
///
/// Модератор видит жалобу, стороны и саму сделку. Решение требует и исхода, и
/// объяснения: обе стороны получат его текстом, и без объяснения любое решение
/// читается как несправедливое.
class DisputeQueueScreen extends ConsumerWidget {
  const DisputeQueueScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final queue = ref.watch(disputeQueueProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Споры'),
        leading: IconButton(
          tooltip: 'Назад',
          onPressed: () => context.canPop() ? context.pop() : context.go('/home'),
          icon: TkIcon(TkIcons.arrowLeft, size: 20, color: scheme.onSurface),
        ),
      ),
      body: queue.when(
        loading: () => const TkSkeletonList(count: 2),
        error: (e, _) => TkErrorState(
          message: '$e',
          onRetry: () => ref.invalidate(disputeQueueProvider),
        ),
        data: (items) {
          if (items.isEmpty) {
            return const TkEmptyState(
              icon: TkIcons.scales,
              title: 'Споров нет',
              description: 'Разобранные споры уходят отсюда сами',
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(disputeQueueProvider),
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) => _DisputeCard(dispute: items[i]),
            ),
          );
        },
      ),
    );
  }
}

class _DisputeCard extends ConsumerStatefulWidget {
  const _DisputeCard({required this.dispute});

  final Dispute dispute;

  @override
  ConsumerState<_DisputeCard> createState() => _DisputeCardState();
}

class _DisputeCardState extends ConsumerState<_DisputeCard> {
  bool _busy = false;

  Future<void> _resolve() async {
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (_) => _ResolveDialog(dispute: widget.dispute),
    );
    if (result == null) return;

    setState(() => _busy = true);
    try {
      await ref.read(disputeActionsProvider).resolve(
            widget.dispute.id,
            outcome: result.$1,
            resolution: result.$2,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Решение отправлено обеим сторонам')),
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
    final d = widget.dispute;

    return TkCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            d.jobTitle.isEmpty ? 'Сделка' : d.jobTitle,
            style: TkText.h3,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            'Заказчик: ${d.clientName} · Исполнитель: ${d.ownerName}',
            style: TkText.caption.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: TkRadius.cardR,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Жалоба ${d.openedByClient ? 'заказчика' : 'исполнителя'}'
                  '${d.createdAt != null ? ' · ${tkShortDate(d.createdAt)}' : ''}',
                  style: TkText.caption.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(d.reason, style: TkText.body),
              ],
            ),
          ),
          if (d.photos.isNotEmpty) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 92,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: d.photos.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, i) => ClipRRect(
                  borderRadius: TkRadius.cardR,
                  child: Image.network(d.photos[i], width: 120, fit: BoxFit.cover),
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => context.push('/deals/${d.dealId}'),
                  child: const Text('Смотреть сделку'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: _busy ? null : _resolve,
                  child: _busy
                      ? const SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Вынести решение'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ResolveDialog extends StatefulWidget {
  const _ResolveDialog({required this.dispute});

  final Dispute dispute;

  @override
  State<_ResolveDialog> createState() => _ResolveDialogState();
}

class _ResolveDialogState extends State<_ResolveDialog> {
  final _text = TextEditingController();
  String _outcome = 'compromise';

  static const _minLength = 20;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final short = _text.text.trim().length < _minLength;

    return AlertDialog(
      title: const Text('Решение по спору'),
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
                  label: 'Прав заказчик',
                  selected: _outcome == 'client',
                  onTap: () => setState(() => _outcome = 'client'),
                ),
                TkChip(
                  label: 'Прав исполнитель',
                  selected: _outcome == 'owner',
                  onTap: () => setState(() => _outcome = 'owner'),
                ),
                TkChip(
                  label: 'Компромисс',
                  selected: _outcome == 'compromise',
                  onTap: () => setState(() => _outcome = 'compromise'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TkTextField(
              controller: _text,
              label: 'Обоснование',
              hint: 'На что вы опирались: фотографии, отметки времени, переписка',
              maxLines: 4,
              maxLength: 1000,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 6),
            Text(
              'Текст получат обе стороны. Решение в пользу заказчика отменяет сделку, '
              'остальные — закрывают её как выполненную.',
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
          onPressed: short ? null : () => Navigator.pop(context, (_outcome, _text.text.trim())),
          child: const Text('Отправить'),
        ),
      ],
    );
  }
}
