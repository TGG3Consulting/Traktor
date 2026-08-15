import 'package:api_client/api_client.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_settings.dart';
import 'equipment_providers.dart';

/// Список «Моя техника» (ТЗ §2.5, прототип `equipment`).
///
/// Без техники исполнитель не может делать ставки, поэтому пустой экран не
/// молчит, а прямо говорит, что делать дальше.
class EquipmentListScreen extends ConsumerWidget {
  const EquipmentListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final items = ref.watch(myEquipmentProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Моя техника'),
        leading: IconButton(
          tooltip: 'Назад',
          onPressed: () => context.canPop() ? context.pop() : context.go('/home'),
          icon: TkIcon(TkIcons.arrowLeft, size: 20, color: scheme.onSurface),
        ),
      ),
      body: items.when(
        loading: () => const TkSkeletonList(count: 2),
        error: (e, _) => TkErrorState(
          message: '$e',
          onRetry: () => ref.invalidate(myEquipmentProvider),
        ),
        data: (list) {
          if (list.isEmpty) {
            return const TkEmptyState(
              icon: TkIcons.wrench,
              title: 'Техники пока нет',
              description: 'Добавьте первую машину — без техники нельзя делать ставки',
            );
          }
          final unverified = list.where((e) => e.status == 'unverified').toList();
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(myEquipmentProvider),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
              children: [
                for (final e in list) ...[
                  _EquipmentCard(item: e),
                  const SizedBox(height: 10),
                ],
                // Мотиватор показываем только когда есть что улучшить, и
                // ведём сразу к нужной карточке, а не в общий список.
                if (unverified.isNotEmpty)
                  _VerifyHint(
                    onTap: () => context.push('/equipment/${unverified.first.id}/edit/4'),
                    title: unverified.first.title,
                  ),
              ],
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/equipment/new'),
        icon: const TkIcon(TkIcons.plus, size: 18, color: Colors.white),
        label: const Text('Добавить технику'),
      ),
    );
  }
}

class _EquipmentCard extends ConsumerWidget {
  const _EquipmentCard({required this.item});

  final Equipment item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final lang = (ref.watch(appSettingsProvider).locale ?? const Locale('ru')).languageCode;
    final category = item.categoryTitle(lang);

    return TkCard(
      onTap: () => context.push('/equipment/${item.id}/edit/${item.draftStep}'),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Место под фото: загрузка изображений появится вместе с хранилищем,
          // до тех пор — иконка вместо пустого прямоугольника.
          Container(
            width: 64,
            height: 64,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: TkRadius.cardR,
            ),
            child: TkIcon(TkIcons.wrench, size: 24, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title.isEmpty ? 'Черновик карточки' : item.title,
                  style: TkText.h3,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    if (category.isNotEmpty) category,
                    if (item.year != null) '${item.year} г',
                  ].join(' · '),
                  style: TkText.caption.copyWith(color: scheme.onSurfaceVariant),
                ),
                if (item.priceHour != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Аренда: ${tkMoney(item.priceHour)}/ч'
                    '${item.priceShift != null ? ' · ${tkMoney(item.priceShift)}/смена' : ''}',
                    style: TkText.caption.copyWith(
                      color: TkColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    _StatusBadge(status: item.status),
                    if (item.wins > 0) ...[
                      const SizedBox(width: 8),
                      Text(
                        '${item.wins} ${tkPlural(item.wins, 'работа', 'работы', 'работ')}',
                        style: TkText.caption.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ],
                ),
                if (item.isRejected && item.rejectReason.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Отклонено: ${item.rejectReason}',
                    style: TkText.caption.copyWith(color: TkColors.error),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'verified' => ('Проверен', TkColors.success),
      'pending' => ('На проверке', TkColors.warning),
      'unverified' => ('Без проверки', Theme.of(context).colorScheme.outline),
      'rejected' => ('Отклонено', TkColors.error),
      _ => ('Черновик', Theme.of(context).colorScheme.outline),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: const BorderRadius.all(Radius.circular(10)),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white),
      ),
    );
  }
}

/// Мягкий мотиватор добавить документы: не запрет, а объяснение выгоды.
class _VerifyHint extends StatelessWidget {
  const _VerifyHint({required this.onTap, required this.title});

  final VoidCallback onTap;
  final String title;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: TkRadius.cardR,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: TkColors.primary.withValues(alpha: 0.1),
          borderRadius: TkRadius.cardR,
        ),
        child: Row(
          children: [
            const TkIcon(TkIcons.lightbulb, size: 20, color: TkColors.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Проверенные получают заметно больше заказов — добавьте документы '
                'для «$title»',
                style: TkText.caption.copyWith(color: TkColors.primary),
              ),
            ),
            const TkIcon(TkIcons.caretRight, size: 16, color: TkColors.primary),
          ],
        ),
      ),
    );
  }
}
