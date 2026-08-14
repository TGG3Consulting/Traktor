import 'package:api_client/api_client.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'offers_providers.dart';

/// «Мои ставки» — вкладка исполнителя (ТЗ §1.9).
///
/// Здесь исполнитель видит, что происходит с его предложениями: где ждут
/// ответа, где заказчик предложил свою цену, где выбрали его, а где — другого.
/// Без этого экрана единственный способ узнать судьбу отклика — открывать
/// каждое задание по очереди.
class MyOffersTab extends ConsumerWidget {
  const MyOffersTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offers = ref.watch(myOffersProvider);

    return offers.when(
      loading: () => const TkSkeletonList(),
      error: (e, _) => TkErrorState(
        message: '$e',
        onRetry: () => ref.invalidate(myOffersProvider),
      ),
      data: (list) {
        if (list.isEmpty) {
          return const TkEmptyState(
            icon: TkIcons.chartBar,
            title: 'Предложений пока нет',
            description: 'Откликайтесь на задания из ленты — они появятся здесь',
          );
        }
        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(myOffersProvider),
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) => _MyOfferCard(offer: list[i]),
          ),
        );
      },
    );
  }
}

class _MyOfferCard extends StatelessWidget {
  const _MyOfferCard({required this.offer});

  final Offer offer;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (label, color, hint) = _state(offer);

    return TkCard(
      onTap: () => context.go('/jobs/${offer.jobId}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  offer.kind == 'accept' ? 'Принял цену заказчика' : 'Своё предложение',
                  style: TkText.h3,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(label,
                    style: TkText.caption.copyWith(color: color, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                tkMoney(offer.price, currency: offer.currency),
                style: TkText.price.copyWith(fontSize: 20, color: TkColors.primary),
              ),
              if (offer.hasCounter && offer.status == 'counter_offered') ...[
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text(
                    'заказчик: ${tkMoney(offer.clientCounterPrice, currency: offer.currency)}',
                    style: TkText.caption.copyWith(color: TkColors.warning),
                  ),
                ),
              ],
            ],
          ),
          if (hint.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(hint, style: TkText.caption.copyWith(color: scheme.onSurfaceVariant)),
          ],
          if (offer.declineReason.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('Причина: ${offer.declineReason}',
                style: TkText.caption.copyWith(color: scheme.onSurfaceVariant)),
          ],
        ],
      ),
    );
  }

  /// Состояние предложения словами, а не кодом статуса.
  (String, Color, String) _state(Offer o) => switch (o.status) {
        'accepted' => ('Вас выбрали', TkColors.success, 'Заказчик подтверждает сделку'),
        'declined' => ('Отклонено', TkColors.error, ''),
        'withdrawn' => ('Вы сняли', const Color(0xFF8A919B), ''),
        'counter_offered' => (
            'Встречная цена',
            TkColors.warning,
            'Заказчик предложил свою цену — примите её или предложите другую'
          ),
        _ => ('Ждёт ответа', TkColors.info, 'Заказчик ещё не принял решение'),
      };
}
