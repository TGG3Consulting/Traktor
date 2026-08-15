import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'job_detail_screen.dart';
import 'jobs_providers.dart';

/// Выбранное задание в двухколоночной раскладке (ТЗ §4.2). На телефоне не
/// используется: там карточка открывает отдельный экран.
final selectedJobProvider = StateProvider<String?>((ref) => null);

/// Лента заданий — главный экран исполнителя (ТЗ §2.7, прототип `feed`).
///
/// Чипы-фильтры сверху, карточки с ценой, расстоянием и живым таймером
/// аукциона. Пять состояний экрана (загрузка, содержимое, пусто, ошибка,
/// обновление) — обязательное требование §1.11.
class FeedTab extends ConsumerWidget {
  const FeedTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // На широком экране лента и деталка стоят рядом: иначе половина монитора
    // пустая, а задания листаются по одному (ТЗ §4.2).
    if (TkLayout.isDesktop(context)) return const _TwoPane();
    return const _FeedList();
  }
}

/// Список заданий — он же левая колонка на десктопе.
class _FeedList extends ConsumerWidget {
  const _FeedList({this.compact = false});

  /// В двухколоночной раскладке карточка не уводит на другой экран, а меняет
  /// содержимое правой колонки.
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feed = ref.watch(feedProvider);
    final filters = ref.watch(feedFiltersProvider);
    final scheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: TextField(
            decoration: InputDecoration(
              hintText: 'Поиск заданий',
              prefixIcon: Padding(
                padding: const EdgeInsets.all(12),
                child: TkIcon(TkIcons.magnifyingGlass, size: 18, color: scheme.onSurfaceVariant),
              ),
              isDense: true,
            ),
            textInputAction: TextInputAction.search,
            onSubmitted: (v) => ref.read(feedFiltersProvider.notifier).update(
                  (f) => f.copyWith(query: v),
                ),
          ),
        ),
        _Filters(filters: filters),
        Expanded(
          child: feed.when(
            loading: () => const TkSkeletonList(),
            error: (e, _) => TkErrorState(
              message: '$e',
              onRetry: () => ref.invalidate(feedProvider),
            ),
            data: (jobs) {
              if (jobs.isEmpty) {
                return TkEmptyState(
                  icon: TkIcons.magnifyingGlass,
                  title: 'Заданий поблизости нет',
                  description: 'Попробуйте увеличить радиус или снять фильтр по режиму',
                  actionLabel: 'Радиус 100 км',
                  onAction: () => ref
                      .read(feedFiltersProvider.notifier)
                      .update((f) => f.copyWith(radiusKm: 100, mode: '')),
                );
              }
              return RefreshIndicator(
                onRefresh: () async => ref.invalidate(feedProvider),
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 90),
                  itemCount: jobs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final j = jobs[i];
                    final category = ref.watch(categoryByIdProvider(j.categoryId));
                    return TkJobCard(
                      title: j.title,
                      icon: TkIcons.byName(category?.icon ?? 'wrench'),
                      city: j.address,
                      distanceM: j.distanceM,
                      price: j.budgetAmount,
                      // Стартовую цену зачёркиваем только когда есть ставки —
                      // иначе в карточке два одинаковых числа подряд.
                      startPrice: null,
                      currency: j.currency,
                      isAuction: j.isAuction,
                      auctionEndsAt: j.auction?.endsAt,
                      offersCount: j.offersCount,
                      viewsCount: j.viewsCount,
                      workersCount: j.workersCount,
                      hasPhoto: j.photos.isNotEmpty,
                      onTap: () => compact
                          ? ref.read(selectedJobProvider.notifier).state = j.id
                          : context.go('/jobs/${j.id}'),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Двухколоночная лента для десктопа (ТЗ §4.2): список слева, выбранное
/// задание справа. Так исполнитель просматривает десяток заданий, не теряя
/// позицию в списке.
class _TwoPane extends ConsumerWidget {
  const _TwoPane();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final selected = ref.watch(selectedJobProvider);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(width: TkLayout.listPane, child: _FeedList(compact: true)),
        VerticalDivider(width: 1, color: scheme.outlineVariant),
        Expanded(
          child: selected == null
              ? const TkEmptyState(
                  icon: TkIcons.clipboardText,
                  title: 'Выберите задание',
                  description: 'Слева — лента, справа откроется карточка',
                )
              : JobDetailScreen(key: ValueKey(selected), jobId: selected, embedded: true),
        ),
      ],
    );
  }
}

/// Чипы-фильтры (ТЗ §2.7): радиус, режим, сортировка.
class _Filters extends ConsumerWidget {
  const _Filters({required this.filters});

  final FeedFilters filters;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void update(FeedFilters Function(FeedFilters) fn) =>
        ref.read(feedFiltersProvider.notifier).update(fn);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: Row(
        children: [
          for (final km in [10.0, 25.0, 50.0, 100.0]) ...[
            TkChip(
              label: '${km.round()} км',
              selected: filters.radiusKm == km,
              onTap: () => update((f) => f.copyWith(radiusKm: km)),
            ),
            const SizedBox(width: 8),
          ],
          Container(width: 1, height: 22, color: Theme.of(context).colorScheme.outlineVariant),
          const SizedBox(width: 8),
          TkChip(
            label: 'Все режимы',
            selected: filters.mode.isEmpty,
            onTap: () => update((f) => f.copyWith(mode: '')),
          ),
          const SizedBox(width: 8),
          TkChip(
            label: 'Аукцион',
            selected: filters.mode == 'auction',
            onTap: () => update((f) => f.copyWith(mode: 'auction')),
          ),
          const SizedBox(width: 8),
          TkChip(
            label: 'Фикс-цена',
            selected: filters.mode == 'fixed',
            onTap: () => update((f) => f.copyWith(mode: 'fixed')),
          ),
          const SizedBox(width: 8),
          Container(width: 1, height: 22, color: Theme.of(context).colorScheme.outlineVariant),
          const SizedBox(width: 8),
          TkChip(
            label: 'Новые',
            selected: filters.sort == 'new',
            onTap: () => update((f) => f.copyWith(sort: 'new')),
          ),
          const SizedBox(width: 8),
          TkChip(
            label: 'Ближе',
            selected: filters.sort == 'near',
            onTap: () => update((f) => f.copyWith(sort: 'near')),
          ),
          const SizedBox(width: 8),
          TkChip(
            label: 'Дороже',
            selected: filters.sort == 'price',
            onTap: () => update((f) => f.copyWith(sort: 'price')),
          ),
          const SizedBox(width: 8),
          TkChip(
            label: 'Скоро финиш',
            selected: filters.sort == 'ending',
            onTap: () => update((f) => f.copyWith(sort: 'ending')),
          ),
        ],
      ),
    );
  }
}
