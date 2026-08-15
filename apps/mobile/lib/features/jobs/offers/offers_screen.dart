import 'package:api_client/api_client.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../chat/open_chat.dart';
import '../jobs_providers.dart';
import 'offers_providers.dart';

/// Экран откликов заказчика (ТЗ §2.10, прототип `offers`).
///
/// Три действия по карточке: выбрать, предложить свою цену (один раунд) и
/// отклонить. Выбор исполнителя необратим для остальных — поэтому он всегда
/// через подтверждение с явным описанием последствий.
class JobOffersScreen extends ConsumerWidget {
  const JobOffersScreen({super.key, required this.jobId});

  final String jobId;

  /// Заголовок с числом живых предложений: отклонённые в счётчике не нужны.
  String _title(List<Offer>? offers) {
    if (offers == null) return 'Отклики';
    final live = offers.where((o) => o.isActive || o.isAccepted).length;
    return 'Отклики · $live';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offers = ref.watch(jobOffersProvider(jobId));
    final job = ref.watch(jobProvider(jobId));
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(_title(offers.valueOrNull)),
        leading: IconButton(
          tooltip: 'Назад',
          onPressed: () => context.canPop() ? context.pop() : context.go('/jobs/$jobId'),
          icon: TkIcon(TkIcons.arrowLeft, size: 20, color: scheme.onSurface),
        ),
      ),
      body: offers.when(
        loading: () => const TkSkeletonList(count: 2),
        error: (e, _) => TkErrorState(
          message: '$e',
          onRetry: () => ref.invalidate(jobOffersProvider(jobId)),
        ),
        data: (list) {
          if (list.isEmpty) {
            return const TkEmptyState(
              icon: TkIcons.chatCircle,
              title: 'Откликов пока нет',
              description: 'Обычно первые приходят в течение часа после публикации',
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(jobOffersProvider(jobId)),
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              itemCount: list.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) => _OfferCard(
                offer: list[i],
                jobPrice: job.valueOrNull?.budgetAmount,
                jobId: jobId,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _OfferCard extends ConsumerWidget {
  const _OfferCard({required this.offer, required this.jobId, this.jobPrice});

  final Offer offer;
  final String jobId;
  final int? jobPrice;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final decided = !offer.isActive;

    return Opacity(
      opacity: decided && !offer.isAccepted ? 0.6 : 1,
      child: TkCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: scheme.surfaceContainerHighest,
                  child: TkIcon(TkIcons.user, size: 18, color: scheme.onSurfaceVariant),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(offer.ownerName, style: TkText.h3),
                          if (offer.ownerVerified) ...[
                            const SizedBox(width: 4),
                            const TkIcon(TkIcons.checkCircle, size: 14, color: TkColors.success),
                          ],
                          if (offer.ownerRatingCount > 0) ...[
                            const SizedBox(width: 6),
                            const TkIcon(TkIcons.starFill, size: 12, color: TkColors.warning),
                            const SizedBox(width: 2),
                            Text(
                              offer.ownerRating.toStringAsFixed(1).replaceAll('.', ','),
                              style: TkText.caption.copyWith(color: scheme.onSurfaceVariant),
                            ),
                          ],
                        ],
                      ),
                      Text(
                        offer.eta.isEmpty ? _when(offer) : 'Сможет: ${offer.eta}',
                        style: TkText.caption.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                // «Вопрос» доступен всегда, в том числе по решённому отклику:
                // уточнить детали после выбора — обычное дело (прототип §2.10).
                IconButton(
                  tooltip: 'Написать',
                  onPressed: () =>
                      openChatAndGo(context, ref, jobId, ownerId: offer.ownerId),
                  icon: TkIcon(TkIcons.chatCircle, size: 20, color: scheme.onSurfaceVariant),
                ),
                _StatusChip(offer: offer),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  tkMoney(offer.price, currency: offer.currency),
                  style: TkText.price.copyWith(
                    fontSize: 22,
                    color: offer.kind == 'counter' ? TkColors.warning : TkColors.primary,
                  ),
                ),
                const SizedBox(width: 8),
                if (offer.kind == 'counter' && jobPrice != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Text(
                      'ваша цена ${tkMoney(jobPrice, currency: offer.currency)}',
                      style: TkText.caption.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
              ],
            ),
            // Строка про ожидание ответа нужна только пока торг идёт: после
            // выбора исполнителя она вводила бы в заблуждение.
            if (offer.hasCounter && offer.status == 'counter_offered') ...[
              const SizedBox(height: 6),
              Text(
                'Вы предложили ${tkMoney(offer.clientCounterPrice, currency: offer.currency)} — '
                'ждём ответа исполнителя',
                style: TkText.caption.copyWith(color: TkColors.warning),
              ),
            ],
            if (offer.comment.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(offer.comment, style: TkText.body),
            ],
            if (offer.declineReason.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Отклонено: ${offer.declineReason}',
                  style: TkText.caption.copyWith(color: scheme.onSurfaceVariant)),
            ],
            if (!decided) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _decline(context, ref),
                      child: const Text('Отклонить'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (!offer.hasCounter)
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _counter(context, ref),
                        child: const Text('Своя цена'),
                      ),
                    ),
                  if (!offer.hasCounter) const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => _accept(context, ref),
                      child: const Text('Выбрать'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _when(Offer o) {
    final created = o.createdAt;
    if (created == null) return '';
    final ago = DateTime.now().difference(created);
    if (ago.inMinutes < 1) return 'только что';
    if (ago.inHours < 1) return '${ago.inMinutes} мин назад';
    if (ago.inDays < 1) return '${ago.inHours} ч назад';
    return tkShortDate(created);
  }

  Future<void> _accept(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Выбрать этого исполнителя?'),
        content: Text(
          'Цена ${tkMoney(offer.hasCounter ? offer.clientCounterPrice : offer.price, currency: offer.currency)} '
          'станет ценой сделки. Остальные предложения будут отклонены, '
          'исполнители получат уведомление.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Выбрать')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await _run(context, ref, () => ref.read(offerActionsProvider).accept(jobId, offer.id),
        success: 'Исполнитель выбран');
  }

  Future<void> _decline(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Отклонить предложение?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Причину указывать необязательно, но исполнителю будет понятнее.'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: const InputDecoration(hintText: 'Например: дорого для этого объёма'),
              maxLength: 120,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: TkColors.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Отклонить'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await _run(
      context,
      ref,
      () => ref.read(offerActionsProvider).decline(jobId, offer.id, reason: controller.text.trim()),
      success: 'Предложение отклонено',
    );
  }

  Future<void> _counter(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController(text: '${offer.price}');
    final price = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ваша цена'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Предложить свою цену можно один раз — дальше решает исполнитель.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(suffixText: '֏'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
          FilledButton(
            onPressed: () => Navigator.pop(context, int.tryParse(controller.text)),
            child: const Text('Отправить'),
          ),
        ],
      ),
    );
    if (price == null || price <= 0 || !context.mounted) return;
    await _run(context, ref, () => ref.read(offerActionsProvider).counter(jobId, offer.id, price),
        success: 'Встречная цена отправлена');
  }

  /// Общая обёртка: показать результат или причину отказа. Молчаливый провал
  /// действия — худший из возможных вариантов.
  Future<void> _run(BuildContext context, WidgetRef ref, Future<void> Function() action,
      {required String success}) async {
    try {
      await action();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(success)));
      }
    } on ApiException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.detail)));
      }
    }
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.offer});

  final Offer offer;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (offer.status) {
      'accepted' => ('Выбран', TkColors.success),
      'declined' => ('Отклонён', TkColors.error),
      'withdrawn' => ('Отозван', Theme.of(context).colorScheme.onSurfaceVariant),
      'counter_offered' => ('Ждём ответа', TkColors.warning),
      _ => (offer.kind == 'counter' ? 'Своя цена' : 'Принял цену', TkColors.info),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label,
          style: TkText.caption.copyWith(color: color, fontWeight: FontWeight.w600)),
    );
  }
}
